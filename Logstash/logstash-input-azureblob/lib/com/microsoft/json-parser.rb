# encoding: utf-8

require Dir[ File.dirname(__FILE__) + "/../../*_jars.rb" ].first

# Interface for a class that reads strings of arbitrary length from the end of a container
class LinearReader
    # returns [content, are_more_bytes_available] 
    # content is a string
    # are_more_bytes_available is a boolean stating if the container has more bytes to read
    def read()
        raise 'not implemented'
    end
end

class JsonParser
  def initialize(logger, linear_reader)
    @logger = logger
    @linear_reader = linear_reader
    @stream_base_offset = 0

    @stream_reader = StreamReader.new(@logger,@linear_reader)
    @parser_factory = javax::json::Json.createParserFactory(nil)
    @parser = @parser_factory.createParser(@stream_reader)
  end

  def parse(on_json_cbk, on_skip_malformed_cbk)
    completed = false
    while !completed
      completed, start_index, end_index = parse_single_object(on_json_cbk)
      if !completed

        # if current position in the stream is not a well formed JSON then
        # I can skip all future chars until I find a '{' so I won't have to create the parser for each char
        json_candidate_start_index = @stream_reader.find('{',   end_index)
        json_candidate_start_index = @stream_reader.get_cached_stream_length - 1 if json_candidate_start_index.nil?
        @logger.debug("JsonParser::parse Skipping Malformed JSON (start: #{start_index} end: #{end_index} candidate: #{json_candidate_start_index - 1}).  Resetting the parser") 
        end_index = json_candidate_start_index - 1  

        on_skip_malformed_cbk.call(@stream_reader.get_stream_buffer(start_index, end_index))
        @stream_reader.drop_stream(end_index + 1)
        @stream_reader.reset_cached_stream_index(0)

        @stream_base_offset = 0
        @parser.close()
        if @stream_reader.get_cached_stream_length <= 1
          on_skip_malformed_cbk.call(@stream_reader.get_stream_buffer(0, -1))
          return
        end
        @parser  = @parser_factory.createParser(@stream_reader)
      end
    end
  end
  
  private
  def parse_single_object(on_json_cbk)
    depth = 0
    stream_start_offset = 0
    stream_end_offset = 0
    while @parser.hasNext
      event = @parser.next
  
      if event == javax::json::stream::JsonParser::Event::START_OBJECT
        depth = depth + 1
      elsif event == javax::json::stream::JsonParser::Event::END_OBJECT
        depth = depth - 1 # can't be negative because the parser handles the format correctness
  
        if depth == 0
          stream_end_offset = @parser.getLocation() .getStreamOffset() - 1
          @logger.debug ("JsonParser::parse_single_object Json  object found stream_start_offset: #{stream_start_offset} stream_end_offset: #{stream_end_offset}")
  
          on_json_cbk.call(@stream_reader.get_stream_buffer(stream_start_offset - @stream_base_offset,  stream_end_offset - @stream_base_offset))
          stream_start_offset = stream_end_offset + 1
  
          #Drop parsed bytes
          @stream_reader.drop_stream(stream_end_offset  - @stream_base_offset)
          @stream_base_offset = stream_end_offset
        end
  
      end
    end
    return true
    rescue javax::json::stream::JsonParsingException => e
      return false, stream_start_offset - @stream_base_offset, 
      @parser.getLocation().getStreamOffset() - 1 - @stream_base_offset
    rescue javax::json::JsonException, java::util::NoSuchElementException => e
      @logger.debug("JsonParser::parse_single_object Exception stream_start_offset: #{stream_start_offset} stream_end_offset: #{stream_end_offset}")
      raise e
  end
end # class JsonParser
  
class StreamReader < java::io::Reader
  def initialize(logger, reader)
    super()
    @logger = logger
    @reader = reader

    @stream_buffer = ""
    @is_full_stream_read = false
    @index = 0
    @stream_buffer_length = 0
  end

  def markSupported
    return false
  end

  def close
  end

  def get_cached_stream_length
    return @stream_buffer_length
  end

  def get_cached_stream_index
    return @index
  end

  def get_stream_buffer(start_index, end_index)
    return @stream_buffer[start_index..end_index]
  end

  def find(substring, offset)
    return @stream_buffer.index(substring, offset)
  end

  def drop_stream(until_offset)
    @logger.debug("StreamReader::drop_stream until_offset:#{until_offset} index: #{@index}")
    if @index < until_offset
      return
    end
    @stream_buffer = @stream_buffer[until_offset..-1]
    @index = @index - until_offset
    @stream_buffer_length = @stream_buffer_length - until_offset
  end

  def reset_cached_stream_index(new_offset)
    @logger.debug("StreamReader::reset_cached_stream_index new_offset:#{new_offset} index: #{@index}")
    if new_offset < 0
      return
    end
    @index = new_offset
  end

  #offset refers to the offset in the output bufferhttp://docs.oracle.com/javase/7/docs/api/java/io/Reader.html#read(char[],%20int,%20int)
  def read(buf, offset, len)
    @logger.debug("StreamReader::read #{offset} #{len}  | stream index: #{@index} stream length: #{@stream_buffer_length}")
    are_all_bytes_available = true
    if @index + len - offset > @stream_buffer_length
      are_all_bytes_available = fill_stream_buffer(@index + len - offset - @stream_buffer_length)
    end

    if (@stream_buffer_length - @index) < len
      len = @stream_buffer_length - @index
      @logger.debug("StreamReader::read #{offset} Actual length: #{len}")
    end

    if len > 0
      #TODO: optimize this
      jv_string = @stream_buffer[@index..@index+len-1].to_java
      jv_bytes_array = jv_string.toCharArray()
      java::lang::System.arraycopy(jv_bytes_array, 0, buf, offset, len)

      @index = @index + len
    end

    if !are_all_bytes_available && len == 0
      @logger.debug("StreamReader::read end of stream")
      return -1
    else
      return len
    end

    rescue java::lang::IndexOutOfBoundsException => e
      @logger.debug("StreamReader::read IndexOutOfBoundsException")
      raise e
    rescue java::lang::ArrayStoreException => e
      @logger.debug("StreamReader::read ArrayStoreException")
      raise e
    rescue java::lang::NullPointerException => e
      @logger.debug("StreamReader::read NullPointerException")
      raise e
  end

  private
  def fill_stream_buffer(len)
    @logger.debug("StreamReader::fill_stream_buffer #{len}")
    bytes_read = 0
    while bytes_read < len
      content, are_more_bytes_available = @reader.read
      if !content.nil? && content.length > 0
        @stream_buffer << content
        @stream_buffer_length  = @stream_buffer_length + content.length
        bytes_read = bytes_read + content.length
      end
      if !are_more_bytes_available
        return false
      end
    end
    return true
  end

end # class StreamReader
