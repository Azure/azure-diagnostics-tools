# encoding: utf-8
require "logstash/inputs/base"
require "logstash/namespace"

require "securerandom"
require "open-uri"
require "thread"

require Dir[ File.dirname(__FILE__) + "/../../*_jars.rb" ].first

# Reads events from Azure event-hub
class LogStash::Inputs::Azureeventhub < LogStash::Inputs::Base

  config_name "azureeventhub"
  milestone 1

  default :codec, "json"
  
  config :key, :validate => :string
  config :username, :validate => :string
  config :namespace, :validate => :string
  config :domain, :validate => :string, :default => "servicebus.windows.net"
  config :port, :validate => :number, :default => 5671
  config :receive_credits, :validate => :number, :default => 1000
  
  config :eventhub, :validate => :string
  config :partitions, :validate => :number
  config :consumer_group, :validate => :string, :default => "$default"
  
  config :time_since_epoch_millis, :validate => :number, :default => Time.now.utc.to_i * 1000
  config :thread_wait_sec, :validate => :number, :default => 5
  
  
  def initialize(*args)
    super(*args)
  end # def initialize

  public
  def register
  end # def register

  def get_pay_load(message)
    return nil, nil if not message
    annotationMap = nil
    body = nil
    message.getPayload().each do |section|
      if section.java_kind_of? org::apache::qpid::amqp_1_0::type::messaging::MessageAnnotations
        annotationMap = section.getValue()
      elsif section.java_kind_of? org::apache::qpid::amqp_1_0::type::messaging::Data or section.java_kind_of? org::apache::qpid::amqp_1_0::type::messaging::AmqpValue
          body = section.getValue().to_s.gsub("\\x5c", "\\")
      end
    end
    return body, annotationMap
  end
  
  def process(output_queue, receiver, partition, last_event_offset)
    while !stop?
      begin
        msg = receiver.receive(10)
        if msg
          body, annotationMap = get_pay_load(msg)
          last_event_offset = annotationMap.get(org::apache::qpid::amqp_1_0::type::Symbol.valueOf("x-opt-offset")) unless annotationMap.nil?
          @logger.debug("[#{partition.to_s.rjust(2,"0")}] Event: #{body[0..50] unless body.nil?}... " <<
            "Offset: #{annotationMap.get(org::apache::qpid::amqp_1_0::type::Symbol.valueOf("x-opt-offset")) unless annotationMap.nil? } " <<
            "Time: #{annotationMap.get(org::apache::qpid::amqp_1_0::type::Symbol.valueOf("x-opt-enqueued-time")).to_s unless annotationMap.nil? } " <<
            "Sequence: #{annotationMap.get(org::apache::qpid::amqp_1_0::type::Symbol.valueOf("x-opt-sequence-number")).to_s unless annotationMap.nil? }")

          codec.decode(body) do |event|
            decorate(event)
            output_queue << event
          end
          receiver.acknowledge(msg)
        else
          error = receiver.getError()
          if error
            @logger.debug("[#{partition.to_s.rjust(2,"0")}] Receive error: #{error.to_s}")
            receiver.close()
            return last_event_offset
          else
            @logger.debug("[#{partition.to_s.rjust(2,"0")}] No message")
            sleep(@thread_wait_sec)
          end
        end
      end
    end
  rescue LogStash::ShutdownSignal => e
    @logger.debug("[#{partition.to_s.rjust(2,"0")}] ShutdownSignal received")
    raise e
  rescue org::apache::qpid::amqp_1_0::client::ConnectionErrorException => e
    @logger.error("[#{partition.to_s.rjust(2,"0")}] ConnectionErrorException \nError:#{e}:\nTrace:\n#{e.backtrace}", :exception => e)
    raise e
  rescue => e
    @logger.error("[#{partition.to_s.rjust(2,"0")}] Oh My, An error occurred. \nError:#{e}:\nTrace:\n#{e.backtrace}", :exception => e)
    raise e
  ensure
    return last_event_offset
  end # process
  
  def process_partition(output_queue, partition)
    last_event_offset = nil
    while !stop?
      begin
        filter = nil
        if !last_event_offset.nil?
          @logger.debug("[#{partition.to_s.rjust(2,"0")}] Offset filter: x-opt-offset > #{last_event_offset}")
          filter = SelectorFilter.new "amqp.annotation.x-opt-offset > '" + last_event_offset + "'"
        else
          @logger.debug("[#{partition.to_s.rjust(2,"0")}] Timestamp filter: x-opt-enqueuedtimeutc > #{@time_since_epoch_millis}")
          filter = SelectorFilter.new "amqp.annotation.x-opt-enqueuedtimeutc > '" + @time_since_epoch_millis.to_s + "'"
        end
        filters = { org::apache::qpid::amqp_1_0::type::Symbol.valueOf("apache.org:selector-filter:string") => filter }

        host = @namespace + "." + @domain
        connection = org::apache::qpid::amqp_1_0::client::Connection.new(host, @port, @username, @key, host, true)
        connection.getEndpoint().getDescribedTypeRegistry().register(filter.java_class, WriterFactory.new)
        receiveSession = connection.createSession()
        receiver = receiveSession.createReceiver(@eventhub + "/ConsumerGroups/" + @consumer_group + "/Partitions/" + partition.to_s, org::apache::qpid::amqp_1_0::client::AcknowledgeMode::ALO, "eventhubs-receiver-link-" + partition.to_s, false, filters, nil)
        receiver.setCredit(org::apache::qpid::amqp_1_0::type::UnsignedInteger.valueOf(@receive_credits), true)
        last_event_offset = process(output_queue,receiver,partition, last_event_offset)
      rescue org::apache::qpid::amqp_1_0::client::ConnectionErrorException => e
        sleep(@thread_wait_sec)
        @logger.debug("[#{partition.to_s.rjust(2,"0")}] resetting connection")
        receiver.close()
      end
    end
  rescue LogStash::ShutdownSignal => e
    receiver.close()
    raise e
  rescue => e
    @logger.error("[#{partition.to_s.rjust(2,"0")}] Oh My, An error occurred. \nError:#{e}:\nTrace:\n#{e.backtrace}", :exception => e)
  end # process_partition

  public
  def run(output_queue)
    threads = []
    (0..(@partitions-1)).each do |p_id|
      threads << Thread.new { process_partition(output_queue, p_id) }
    end
    threads.each { |thr| thr.join }
  end # def run

  public
  def teardown
  end # def teardown
end # class LogStash::Inputs::Azureeventhub


class SelectorFilter
  include org::apache::qpid::amqp_1_0::type::messaging::Filter

  def initialize(value)
    @value = value
  end

  def getValue
    return @value
  end

  def toString
    return @value
  end
end

class SelectorFilterWriter < org::apache::qpid::amqp_1_0::codec::AbstractDescribedTypeWriter
  def initialize(registry)
    super(registry)
  end
  
  def onSetValue(value)
    @value = value
  end
  
  def clear
    @value = nil
  end
  
  def getDescriptor
    return org::apache::qpid::amqp_1_0::type::UnsignedLong.valueOf(83483426826);
  end
  
  def createDescribedWriter
    return getRegistry().getValueWriter(@value.getValue());
  end
end

class WriterFactory
  include org::apache::qpid::amqp_1_0::codec::ValueWriter::Factory

  def newInstance(registry)
    return SelectorFilterWriter.new registry
  end
end
