# encoding: utf-8
require "logstash/inputs/base"
require "logstash/namespace"
require "time"
require "azure/storage"
require "set"

class LogStash::Inputs::AzureWADTable < LogStash::Inputs::Base
  class Interrupted < StandardError; end

  config_name "azurewadtable"
  milestone 1

  config :account_name, :validate => :string
  config :access_key, :validate => :string
  config :table_name, :validate => :string
  config :entity_count_to_process, :validate => :string, :default => 100
  config :collection_start_time_utc, :validate => :string, :default => nil #the actual value is set in the ctor (now - data_latency_minutes - 1)
  config :etw_pretty_print, :validate => :boolean, :default => false
  config :idle_delay_seconds, :validate => :number, :default => 15
  config :endpoint, :validate => :string, :default => "core.windows.net"

  # Default 1 minute delay to ensure all data is published to the table before querying.
  # See issue #23 for more: https://github.com/Azure/azure-diagnostics-tools/issues/23
  config :data_latency_minutes, :validate => :number, :default => 1

  # Number of past queries to be run, so we don't miss late arriving data
  config :past_queries_count, :validate => :number, :default => 5

  TICKS_SINCE_EPOCH = Time.utc(0001, 01, 01).to_i * 10000000

  INITIAL_QUERY_SPLIT_PERIOD_MINUTES = 30

  def initialize(*args)
    super(*args)
    if @collection_start_time_utc.nil?
      @collection_start_time_utc = (Time.now - ( 60 * @data_latency_minutes) - 60).iso8601
      @logger.debug("collection_start_time_utc = #{@collection_start_time_utc}")
    end
  end # initialize

  public
  def register
    user_agent = "logstash-input-azurewadtable"
    user_agent << "/" << Gem.latest_spec_for("logstash-input-azurewadtable").version.to_s

    @client = Azure::Storage::Client.create(
      :storage_account_name => @account_name,
      :storage_access_key => @access_key,
      :storage_table_host => "https://#{@account_name}.table.#{@endpoint}",
      :user_agent_prefix => user_agent)
    @azure_table_service = @client.table_client

    @last_timestamp = @collection_start_time_utc
    @idle_delay = @idle_delay_seconds
    @duplicate_detector = DuplicateDetector.new(@logger, @past_queries_count)
    @first_run = true
  end # register

  public
  def run(output_queue)
    while !stop?
      @logger.debug("Starting process method @" + Time.now.to_s);
      process(output_queue)
      @logger.debug("Starting delay of: " + @idle_delay.to_s + " seconds @" + Time.now.to_s);
      sleep @idle_delay
    end # while
  end # run

  public
  def teardown
  end

  def build_latent_query
    @logger.debug("from #{@last_timestamp} to #{@until_timestamp}")
    if @last_timestamp > @until_timestamp
      @logger.debug("last_timestamp is in the future. Will not run any query!")
      return nil
    end
    query_filter = "(PartitionKey gt '#{partitionkey_from_datetime(@last_timestamp)}' and PartitionKey lt '#{partitionkey_from_datetime(@until_timestamp)}')"
    for i in 0..99
      query_filter << " or (PartitionKey gt '#{i.to_s.rjust(19, '0')}___#{partitionkey_from_datetime(@last_timestamp)}' and PartitionKey lt '#{i.to_s.rjust(19, '0')}___#{partitionkey_from_datetime(@until_timestamp)}')"
    end # for block
    query_filter = query_filter.gsub('"','')
    return AzureQuery.new(@logger, @azure_table_service, @table_name, query_filter, @last_timestamp.to_s + "-" + @until_timestamp.to_s, @entity_count_to_process)
  end

  def process(output_queue)
    @until_timestamp = (Time.now - (60 * @data_latency_minutes)).iso8601
    last_good_timestamp = nil

     # split first query so we don't fetch old data several times for no reason
    if @first_run
      @first_run = false
      diff = DateTime.iso8601(@until_timestamp).to_time - DateTime.iso8601(@last_timestamp).to_time
      if diff > INITIAL_QUERY_SPLIT_PERIOD_MINUTES * 60
        @logger.debug("Splitting initial query in two")
        original_until = @until_timestamp

        @until_timestamp = (DateTime.iso8601(@until_timestamp).to_time - INITIAL_QUERY_SPLIT_PERIOD_MINUTES * 60).iso8601

        query = build_latent_query
        @duplicate_detector.filter_duplicates(query, ->(entity) {
          on_new_data(entity, output_queue, last_good_timestamp)
        }, false)

        @last_timestamp = (DateTime.iso8601(@until_timestamp).to_time - 1).iso8601
        @until_timestamp = original_until
      end
    end

    query = build_latent_query
    filter_result = @duplicate_detector.filter_duplicates(query, ->(entity) {
      last_good_timestamp = on_new_data(entity, output_queue, last_good_timestamp)
    })

    if filter_result
      if (!last_good_timestamp.nil?)
        @last_timestamp = last_good_timestamp
      end
    else
      @logger.debug("No new results found.")
    end

  rescue => e
    @logger.error("Oh My, An error occurred. Error:#{e}: Trace: #{e.backtrace}", :exception => e)
    raise
  end # process

  def on_new_data(entity, output_queue, last_good_timestamp)
    #@logger.debug("new event")
    event = LogStash::Event.new(entity.properties)
    event.set("type", @table_name)

    # Help pretty print etw files
    if (@etw_pretty_print && !event.get("EventMessage").nil? && !event.get("Message").nil?)
      @logger.debug("event: " + event.to_s)
      eventMessage = event.get("EventMessage").to_s
      message = event.get("Message").to_s
      @logger.debug("EventMessage: " + eventMessage)
      @logger.debug("Message: " + message)
      if (eventMessage.include? "%")
        @logger.debug("starting pretty print")
        toReplace = eventMessage.scan(/%\d+/)
        payload = message.scan(/(?<!\\S)([a-zA-Z]+)=(\"[^\"]*\")(?!\\S)/)
        # Split up the format string to seperate all of the numbers
        toReplace.each do |key|
          @logger.debug("Replacing key: " + key.to_s)
          index = key.scan(/\d+/).join.to_i
          newValue = payload[index - 1][1]
          @logger.debug("New Value: " + newValue)
          eventMessage[key] = newValue
        end # do block
        event.set("EventMessage", eventMessage)
        @logger.debug("pretty print end. result: " + event.get("EventMessage").to_s)
      end
    end
    decorate(event)
    if event.get('PreciseTimeStamp').is_a?(Time)
      event.set('PreciseTimeStamp', LogStash::Timestamp.new(event.get('PreciseTimeStamp')))
    end
    theTIMESTAMP = event.get('TIMESTAMP')
    if theTIMESTAMP.is_a?(LogStash::Timestamp)
      last_good_timestamp = theTIMESTAMP.to_iso8601
    elsif theTIMESTAMP.is_a?(Time)
      last_good_timestamp = theTIMESTAMP.iso8601
      event.set('TIMESTAMP', LogStash::Timestamp.new(theTIMESTAMP))
    else
      @logger.warn("Found result with invalid TIMESTAMP. " + event.to_hash.to_s)
    end
    output_queue << event
    return last_good_timestamp
  end

  # Windows Azure Diagnostic's algorithm for determining the partition key based on time is as follows:
  # 1. Take time in UTC without seconds.
  # 2. Convert it into .net ticks
  # 3. add a '0' prefix.
  def partitionkey_from_datetime(time_string)
    collection_time = Time.parse(time_string)
    if collection_time
      #@logger.debug("collection time parsed successfully #{collection_time}")
    else
      raise(ArgumentError, "Could not parse the time_string")
    end # if else block

    collection_time -= collection_time.sec
    ticks = to_ticks(collection_time)
    "0#{ticks}"
  end # partitionkey_from_datetime

  # Convert time to ticks
  def to_ticks(time_to_convert)
    #@logger.debug("Converting time to ticks")
    time_to_convert.to_i * 10000000 - TICKS_SINCE_EPOCH
  end # to_ticks

end # LogStash::Inputs::AzureWADTable

class AzureQuery
  def initialize(logger, azure_table_service, table_name, query_str, query_id, entity_count_to_process)
    @logger = logger
    @query_str = query_str
    @query_id = query_id
    @entity_count_to_process = entity_count_to_process
    @azure_table_service = azure_table_service
    @table_name = table_name
    @continuation_token = nil
  end

  def reset
    @continuation_token = nil
  end

  def id
    return @query_id
  end

  def run(on_result_cbk)
    results_found = false
    @logger.debug("[#{@query_id}]Query filter: " + @query_str)
    begin
      @logger.debug("[#{@query_id}]Running query. continuation_token: #{@continuation_token}")
      query = { :top => @entity_count_to_process, :filter => @query_str, :continuation_token => @continuation_token }
      result = @azure_table_service.query_entities(@table_name, query)

      if result and result.length > 0
        results_found = true
        @logger.debug("[#{@query_id}] #{result.length} results found.")
        result.each do |entity|
          on_result_cbk.call(entity)
        end
      end

      @continuation_token = result.continuation_token
    end until !@continuation_token

    return results_found
  end
end

class QueryData
  def initialize(logger, query)
    @logger = logger
    @query = query
    @results_cache = Set.new
  end

  def id
    return @query.id
  end

  def get_unique_id(entity)
    uniqueId = ""
    partitionKey = entity.properties["PartitionKey"]
    rowKey = entity.properties["RowKey"]
    uniqueId << partitionKey << "#" << rowKey
    return uniqueId
  end

  def run_query(on_new_entity_cbk)
    @query.reset
    @query.run( ->(entity) {
      uniqueId = get_unique_id(entity)

      if @results_cache.add?(uniqueId).nil?
        @logger.debug("[#{@query.id}][QueryData] #{uniqueId} already processed")
      else
        @logger.debug("[#{@query.id}][QueryData] #{uniqueId} new item")
        on_new_entity_cbk.call(entity)
      end
    })
  end

  def has_entity(entity)
    return @results_cache.include?(get_unique_id(entity))
  end

end

class DuplicateDetector
  def initialize(logger, past_queries_count)
    @logger = logger
    @past_queries_count = past_queries_count
    @query_cache = []
  end

  def filter_duplicates(query, on_new_item_ckb, should_cache_query = true)
    if query.nil?
      @logger.debug("query is nil")
      return false
    end
    #push in front, pop from the back
    latest_query = QueryData.new(@logger, query)
    @query_cache.insert(0, latest_query)

    found_new_items = false

    # results is most likely empty or has very few items for older queries (most or all should be de-duplicated by run_query)
    index = 0
    @query_cache.each do |query_data|
        query_data.run_query(->(entity) {
        unique_id = query_data.get_unique_id(entity)

        # queries overlap. Check for duplicates in all results
        is_duplicate = false
        for j in 0..@query_cache.length - 1
          if j == index
            next
          end
          q = @query_cache[j]
          if q.has_entity(entity)
            @logger.debug("[#{query_data.id}][filter_duplicates] #{unique_id} was already processed by #{q.id}")
            is_duplicate = true
            break
          end
        end

        if !is_duplicate
          found_new_items = true
          @logger.debug("[#{query_data.id}][filter_duplicates] #{unique_id} new item")
          on_new_item_ckb.call(entity)
        end

      })

      index+=1
    end

    if !should_cache_query
      @logger.debug("Removing first item from queue")
      @query_cache.shift
    end

    @logger.debug("Query Cache length: #{@query_cache.length}")
    until @query_cache.length <= @past_queries_count do
      @query_cache.pop
      @logger.debug("New Query Cache length: #{@query_cache.length}")
    end

    return found_new_items
  end

end
