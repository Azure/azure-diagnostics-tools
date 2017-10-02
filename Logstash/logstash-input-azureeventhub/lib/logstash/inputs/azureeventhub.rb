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
  
  config :key, :validate => :string, :required => true
  config :username, :validate => :string, :required => true
  config :namespace, :validate => :string, :required => true
  config :domain, :validate => :string, :default => "servicebus.windows.net"
  config :port, :validate => :number, :default => 5671
  config :receive_credits, :validate => :number, :default => 999
  
  config :eventhub, :validate => :string, :required => true
  config :partitions, :validate => :number, :required => true
  config :consumer_group, :validate => :string, :default => "$default"
  
  config :time_since_epoch_millis, :validate => :number, :default => Time.now.utc.to_i * 1000
  config :thread_wait_sec, :validate => :number, :default => 5

  config :partition_receiver_epochs, :validate => :hash, :default => {}
  
  
  def initialize(*args)
    super(*args)
  end # def initialize

  public
  def register
    user_agent = "logstash-input-azureeventhub"
    user_agent << "/" << Gem.latest_spec_for("logstash-input-azureeventhub").version.to_s
    com::microsoft::azure::eventhubs::EventHubClient.userAgent = user_agent
  end # def register

  def process(output_queue, receiver, partition, last_event_offset)
    while !stop?
      begin
        events = receiver.receiveSync(10)
        if events
          events.each{ |msg|
            body = msg.getBytes().to_s.gsub("\\x5c", "\\")
            props = msg.getSystemProperties()

            last_event_offset = props.getOffset()
            
            @logger.debug("[#{partition.to_s.rjust(2,"0")}] Event: #{body[0..50] unless body.nil?}... " <<
              "Offset: #{props.getOffset()} " <<
              "Time: #{props.getEnqueuedTime()} " <<
              "Sequence: #{props.getSequenceNumber()}")

            codec.decode(body) do |event|
              decorate(event)
              output_queue << event
            end
          }
        else
          @logger.debug("[#{partition.to_s.rjust(2,"0")}] No message")
        end
      end
    end
  rescue LogStash::ShutdownSignal => e
    @logger.debug("[#{partition.to_s.rjust(2,"0")}] ShutdownSignal received")
    raise e
  rescue => e
    @logger.error("[#{partition.to_s.rjust(2,"0")}] Oh My, An error occurred. Error:#{e}: Trace: #{e.backtrace}", :exception => e)
    raise e
  ensure
    return last_event_offset
  end # process
  
  def process_partition(output_queue, partition, epoch) 
    last_event_offset = nil
    while !stop?
      begin
        host = java::net::URI.new("amqps://" << @namespace << "." << @domain)
        connStr = com::microsoft::azure::eventhubs::ConnectionStringBuilder.new(host, @eventhub, @username, @key).toString()
        ehClient = com::microsoft::azure::eventhubs::EventHubClient.createFromConnectionStringSync(connStr)

        if !epoch.nil?
          if !last_event_offset.nil?
            @logger.debug("[#{partition.to_s.rjust(2,"0")}] Create receiver with epoch=#{epoch} & offset > #{last_event_offset}")
            receiver = ehClient.createEpochReceiverSync(@consumer_group, partition.to_s, last_event_offset, false, epoch)
          else
            @logger.debug("[#{partition.to_s.rjust(2,"0")}] Create receiver with epoch=#{epoch} & timestamp > #{@time_since_epoch_millis}")
            receiver = ehClient.createEpochReceiverSync(@consumer_group, partition.to_s, java::time::Instant::ofEpochMilli(@time_since_epoch_millis), epoch)
          end
        else
          if !last_event_offset.nil?
            @logger.debug("[#{partition.to_s.rjust(2,"0")}] Create receiver with offset > #{last_event_offset}")
            receiver = ehClient.createReceiverSync(@consumer_group, partition.to_s, last_event_offset, false)
          else
            @logger.debug("[#{partition.to_s.rjust(2,"0")}] Create receiver with timestamp > #{@time_since_epoch_millis}")
            receiver = ehClient.createReceiverSync(@consumer_group, partition.to_s, java::time::Instant::ofEpochMilli(@time_since_epoch_millis))
          end
        end
        receiver.setReceiveTimeout(java::time::Duration::ofSeconds(@thread_wait_sec));
        receiver.setPrefetchCount(@receive_credits)

        last_event_offset = process(output_queue, receiver, partition, last_event_offset)
      rescue com::microsoft::azure::eventhubs::EventHubException => e
        sleep(@thread_wait_sec)
        @logger.debug("[#{partition.to_s.rjust(2,"0")}] resetting connection. Error:#{e}: Trace: #{e.backtrace}", :exception => e)
      end
    end
  rescue LogStash::ShutdownSignal => e
    receiver.close()
    raise e
  rescue => e
    @logger.error("[#{partition.to_s.rjust(2,"0")}] Oh My, An error occurred. Error:#{e}: Trace: #{e.backtrace}", :exception => e)
  end # process_partition

  public
  def run(output_queue)
    threads = []
    (0..(@partitions-1)).each do |p_id|
      epoch = partition_receiver_epochs[p_id.to_s] if @partition_receiver_epochs.key?(p_id.to_s)
      threads << Thread.new { process_partition(output_queue, p_id, epoch) }
    end
    threads.each { |thr| thr.join }
  end # def run

  public
  def teardown
  end # def teardown
end # class LogStash::Inputs::Azureeventhub