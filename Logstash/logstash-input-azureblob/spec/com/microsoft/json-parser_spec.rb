require "logstash/devutils/rspec/spec_helper"
require "logging"
require "com/microsoft/json-parser"

describe JsonParser do
    before(:each) do
        @logger = Logging.logger(STDOUT)
        @logger.level = :debug
        @linear_reader = spy

        @on_content = double
        @on_error = double
    end

    def construct(json_str)
        @linear_reader_index = 0
        allow(@linear_reader).to receive(:read) do ->(){
            start_index = @linear_reader_index
            @linear_reader_index = @linear_reader_index + 42
            return json_str[start_index..@linear_reader_index - 1], @linear_reader_index < json_str.length ? true : false
        }.call
        end
        return JsonParser.new(@logger, @linear_reader)
    end

    it 'can parse a complete JSON' do
        json_str = "{\"entity\":{ \"number\":42, \"string\":\"some string\" }}"
        parser = construct(json_str)

        expect(@on_error).to_not receive(:call)
        expect(@on_content).to receive(:call).with(json_str).once

        parser.parse(@on_content, @on_error)
    end

    it 'can parse multiple JSON objects' do
        json_strings = [
            "{\"entity\":{ \"number\":42, \"string\":\"some string\", \"val\":null }}",
            "{\"entity2\":{ \"number2\":422, \"string2\":\"some string2\" }}",
            "{\"entity3\":{ \"number3\":422, \"string3\":\"some string2\", \"array\":[{\"abc\":\"xyz\"}] }}",
            "\n\r{\"entity4\":{ \"number4\":422, \"string4\":\"some string2\", \"empty_array\":[] }}",
            "  {\"entity5\":{ \"number5\":422, \"string5\":\"some string2\" }}",
            " {\"abc\" :\"xyz\"}"
        ]
        content = ""
        json_strings.each do |str|
            content << str
            expect(@on_content).to receive(:call).with(str).ordered
        end
        expect(@on_error).to_not receive(:call)

        parser = construct(content)

        parser.parse(@on_content, @on_error)
    end

    it 'will ignore regular text' do
        not_a_json = "not a json"
        parser = construct(not_a_json)
        skipped_bytes = 0
        expect(@on_content).to_not receive(:call)

        received_malformed_str = ""
        allow(@on_error).to receive(:call) do |malformed_json|
            received_malformed_str << malformed_json
        end

        parser.parse(@on_content, @on_error)

        expect(received_malformed_str).to eq(not_a_json)
    end

    it 'will ignore malformed JSON' do
        not_a_json = "{\"entity\":{ \"number\":42, \"string\":\"comma is missing here ->\" \"<- here\":null }}"
        parser = construct(not_a_json)
        skipped_bytes = 0
        expect(@on_content).to_not receive(:call)

        received_malformed_str = ""
        allow(@on_error).to receive(:call) do |malformed_json|
            received_malformed_str << malformed_json
        end

        parser.parse(@on_content, @on_error)

        expect(received_malformed_str).to eq(not_a_json)
    end

    it 'will skip comma between JSONs' do
        json_str = "{\"entity\":{ \"number\":42, \"string\":\"some string\" }}"
        not_a_json = ","
        parser = construct(json_str+not_a_json+json_str)

        expect(@on_content).to receive(:call).with(json_str).once.ordered
        expect(@on_error).to receive(:call).with(",").once.ordered
        expect(@on_content).to receive(:call).with(json_str).once.ordered

        parser.parse(@on_content, @on_error)
    end

    it 'will skip regular text in the middle' do
        json_str = "{\"entity\":{ \"number\":42, \"string\":\"some string\" }}"
        not_a_json = "not a json"
        parser = construct(json_str+not_a_json+json_str)

        expect(@on_content).to receive(:call).with(json_str).once.ordered
        expect(@on_content).to receive(:call).with(json_str).once.ordered

        received_malformed_str = ""
        allow(@on_error).to receive(:call) do |malformed_json|
            received_malformed_str << malformed_json
        end

        parser.parse(@on_content, @on_error)

        expect(received_malformed_str).to eq(not_a_json)
    end

    it 'can parse multiple JSON objects in between malformed content' do
        strings = [
            [ true, "{\"entity\":{ \"number\":42, \"string\":\"some string\", \"val\":null }}"],
            [ true, "{\"entity2\":{ \"number2\":422, \"string2\":\"some string2\" }}"],
            [ false, ","],
            [ true, "{\"entity3\":{ \"number3\":422, \"string3\":\"some string2\", \"array\":[{\"abc\":\"xyz\"}] }}"],
            [ false, "some random text \n\r"],
            [ true, "{\"entity4\":{ \"number4\":422, \"string4\":\"some string2\", \"empty_array\":[] }}"],
            [ false, "{\"entity\":{ \"number\":42, \"string\":\"some string\" \"val\":null }}  "],
            [ true, "{\"entity5\":{ \"number5\":422, \"string5\":\"some string2\" }}"],
            [ true, " {\"abc\" :\"xyz\"}"]
        ]
        content = ""
        strings.each do |is_valid_json, str|
            content << str
            if is_valid_json
                expect(@on_content).to receive(:call).with(str).ordered
            else
            end
        end
        allow(@on_error).to receive(:call)

        parser = construct(content)

        parser.parse(@on_content, @on_error)
    end

    it 'will batch together malformed content in a single callback' do
        strings = [
            [ true, "{\"entity\":{ \"number\":42, \"string\":\"some string\", \"val\":null }}"],
            [ true, "{\"entity2\":{ \"number2\":422, \"string2\":\"some string2\" }}"],
            [ false, ","],
            [ true, "{\"entity3\":{ \"number3\":422, \"string3\":\"some string2\", \"array\":[{\"abc\":\"xyz\"}] }}"],
            [ false, "some random text \n\r"], #whitespace after malformed data will be part of the malformed string
            [ true, "{\"entity4\":{ \"number4\":422, \"string4\":\"some string2\", \"empty_array\":[] }}"],
            [ false, "{\"entity\":{ \"number\":42, \"string\":\"some string\" \"val\":null }}  "],
            [ true, "{\"entity5\":{ \"number5\":422, \"string5\":\"some string2\" }}"],
            [ true, "\n\r {\"abc\" :\"xyz\"}"] # whitespace after correct jsons will be part of the next json
        ]
        content = ""
        strings.each do |is_valid_json, str|
            content << str
            if is_valid_json
                expect(@on_content).to receive(:call).with(str).ordered
            else
                expect(@on_error).to receive(:call).with(str).ordered
            end
        end

        parser = construct(content)

        parser.parse(@on_content, @on_error)
    end
end

describe StreamReader do
    before(:each) do
        @logger = Logging.logger(STDOUT)
        @logger.level = :debug

        @linear_reader = double
        @stream_reader = StreamReader.new(@logger, @linear_reader)
    end

    it 'does not support mark' do
        expect(@stream_reader.markSupported).to eq(false)
    end

    it 'can read full stream' do
        full_content = "entire content"
        input_buffer = Java::char[full_content.length].new

        expect(@linear_reader).to receive(:read).and_return([full_content, false]).once

        @stream_reader.read(input_buffer, 0, full_content.length)

        expect(java::lang::String.new(input_buffer)).to eq(full_content)
    end

    it 'reads until requested buffer is filled' do
        full_content = "entire content"
        input_buffer = Java::char[full_content.length].new

        expect(@linear_reader).to receive(:read).twice.and_return([full_content[0..full_content.length/2], true],[full_content[full_content.length/2 + 1..-1], true])

        @stream_reader.read(input_buffer, 0, full_content.length)

        expect(java::lang::String.new(input_buffer)).to eq(full_content)
    end

    it 'does not call the read callback when buffer length is 0' do
        expect(@linear_reader).to_not receive(:read)

        @stream_reader.read(nil, 0, 0)
    end

    it 'caches if it reads ahead' do
        full_content = "entire content"
        input_buffer = Java::char[full_content.length].new

        expect(@linear_reader).to receive(:read).and_return([full_content, false]).once

        (0..full_content.length - 1).each do |i|
            @stream_reader.read(input_buffer, i, 1)
        end
        
        expect(java::lang::String.new(input_buffer)).to eq(full_content)
    end

    it 'returns -1 when read callback returns empty and there are no more bytes' do
        expect(@linear_reader).to receive(:read).and_return(["", false]).once

        expect(@stream_reader.read(nil, 0, 42)).to eq(-1)
    end

    it 'will store stream buffer' do
        full_content = "entire content"
        bytes_to_read = 4
        input_buffer = Java::char[bytes_to_read].new

        expect(@linear_reader).to receive(:read).and_return([full_content, false]).once

        @stream_reader.read(input_buffer, 0, bytes_to_read)

        expect(@stream_reader.get_cached_stream_length).to eq(full_content.length)
        expect(@stream_reader.get_cached_stream_index).to eq(bytes_to_read)
        expect(@stream_reader.get_stream_buffer(0,-1)).to eq(full_content)
    end

    it 'will do nothing when drop_stream is called but the until_offset is greater than stream index' do
        full_content = "entire content"
        bytes_to_read = 4
        input_buffer = Java::char[bytes_to_read].new

        expect(@linear_reader).to receive(:read).and_return([full_content, false]).once

        @stream_reader.read(input_buffer, 0, bytes_to_read)

        @stream_reader.drop_stream(@stream_reader.get_cached_stream_index + 1)

        expect(@stream_reader.get_cached_stream_length).to eq(full_content.length)
        expect(@stream_reader.get_cached_stream_index).to eq(bytes_to_read)
        expect(@stream_reader.get_stream_buffer(0,-1)).to eq(full_content)
    end

    it 'will trim buffer stream when drop_stream is called' do
        full_content = "entire content"
        bytes_to_read = 4
        until_offset = bytes_to_read - 2
        input_buffer = Java::char[bytes_to_read].new

        expect(@linear_reader).to receive(:read).and_return([full_content, false]).once

        @stream_reader.read(input_buffer, 0, bytes_to_read)

        @stream_reader.drop_stream(until_offset)

        expect(@stream_reader.get_cached_stream_length).to eq(full_content.length - until_offset)
        expect(@stream_reader.get_cached_stream_index).to eq(bytes_to_read - until_offset)
        expect(@stream_reader.get_stream_buffer(0,-1)).to eq(full_content[until_offset..-1])
    end
end