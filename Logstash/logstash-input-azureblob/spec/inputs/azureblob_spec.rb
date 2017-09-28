require "logstash/devutils/rspec/spec_helper"
require "logging"
require "logstash/inputs/azureblob"

class LogStash::Codecs::JSON
end

describe LogStash::Inputs::LogstashInputAzureblob do

    before(:each) do
        @logger = Logging.logger(STDOUT)
        @logger.level = :debug

        @azure_blob_sdk = double
        @json_codec = double("LogStash::Codecs::JSON", :is_a? => true)
        @other_codec = double("other codec", :is_a? => false)

        @azureblob_input = LogStash::Inputs::LogstashInputAzureblob.new
        @azureblob_input.instance_variable_set(:@logger, @logger)
        @azureblob_input.instance_variable_set(:@file_head_bytes, 0)
        @azureblob_input.instance_variable_set(:@file_tail_bytes, 0)
        @azureblob_input.instance_variable_set(:@azure_blob, @azure_blob_sdk)
        @azureblob_input.instance_variable_set(:@container, double)
        @azureblob_input.instance_variable_set(:@codec, @other_codec)
        allow(@azureblob_input).to receive(:update_registry)
    end

    def set_json_codec
        @azureblob_input.instance_variable_set(:@codec, @json_codec)
    end

    def stub_blob(blob_name, content)
        allow(@azure_blob_sdk).to receive(:get_blob).with(anything(), blob_name, anything()) do |container,  blob_name_arg, props | 
            ->(){
                start_index = 0
                end_index = -1
                start_index = props[:start_range] unless props[:start_range].nil?
                end_index = props[:end_range] unless props[:end_range].nil?

                ret_str = content[start_index..end_index]
                @logger.debug("get_blob(#{start_index},#{end_index}): |#{ret_str}|")
                return double, ret_str
            }.call
        end

        return double(:name => blob_name, :properties => { 
            :content_length => content.length,
            :etag => nil
        })
    end

    it "can parse basic JSON" do
        blob_name = "basic_json"
        json_str = "{\"entity\":{ \"number\":42, \"string\":\"some string\" }}"
        set_json_codec()

        blob = stub_blob(blob_name, json_str)

        allow(@azureblob_input).to receive(:register_for_read).and_return([blob, 0, nil])

        expect(@json_codec).to receive(:decode).with(json_str).ordered
        expect(@json_codec).to_not receive(:decode).ordered

        @azureblob_input.process(nil)
    end

    it "can parse multiple JSONs" do
        blob_name = "multi_json"
        json_str1 = "{\"entity\":{ \"number\":42, \"string\":\"some string\" }}"
        json_str2 = "{\"entity2\":{ \"number2\":422, \"string2\":\"some other string\" }}"
        json_str3 = " \n{\"entity3\":{ \"number2\":422, \"string2\":\"some other string\" }}"
        set_json_codec()

        blob = stub_blob(blob_name, json_str1 + json_str2 + json_str3)

        allow(@azureblob_input).to receive(:register_for_read).and_return([blob, 0, nil])

        expect(@json_codec).to receive(:decode).with(json_str1).once.ordered
        expect(@json_codec).to receive(:decode).with(json_str2).once.ordered
        expect(@json_codec).to receive(:decode).with(json_str3).once.ordered
        expect(@json_codec).to_not receive(:decode).ordered

        @azureblob_input.process(nil)
    end

    it "will parse JSONs from blob start" do
        blob_name = "non_zero_json_start"
        json_str1 = "{\"entity\":{ \"number\":42, \"string\":\"some string\" }}"
        json_str2 = "{\"entity2\":{ \"number2\":422, \"string2\":\"some other string\" }}"
        set_json_codec()

        blob = stub_blob(blob_name, json_str1 + json_str2)

        allow(@azureblob_input).to receive(:register_for_read).and_return([blob, json_str1.length, nil])

        expect(@json_codec).to receive(:decode).with(json_str2).once.ordered
        expect(@json_codec).to_not receive(:decode).ordered

        @azureblob_input.process(nil)
    end

    it "can parse out malformed JSONs" do
        blob_name = "parse_out_malformed"
        json_str1 = "{\"entity\":{ \"number\":42, \"string\":\"some string\" }}"
        json_str2 = "{\"entity2\":{ \"number2\":422, \"string2\":\"some other string\" }}"
        malformed_data = [",", "asdgasfgasfg", "{\"entity\"", "}", "{\"broken_json\":{\"a\":2 \"b\":3}}"]
        set_json_codec()

        malformed_data.each do |malformed|
            blob = stub_blob(blob_name, json_str1 + malformed + json_str2)

            allow(@azureblob_input).to receive(:register_for_read).and_return([blob, 0, nil])

            expect(@json_codec).to receive(:decode).with(json_str1).once.ordered
            expect(@json_codec).to receive(:decode).with(json_str2).once.ordered

            @azureblob_input.process(nil)
        end
    end

    it "can build JSONs with header and tail" do
        blob_name = "head_tail_json"
        json_str1 = "{\"entity\":{ \"number\":42, \"string\":\"some string\" }}"
        json_str2 = "{\"entity2\":{ \"number2\":422, \"string2\":\"some other string\" }}"
        already_parsed = "{\"parsed_json\":true}"
        head = "{\"xyz\":42}{\"entities\" : \n["
        tail = "\n] }{\"abc\":42}\n"
        set_json_codec()
        @azureblob_input.instance_variable_set(:@file_head_bytes, head.length)
        @azureblob_input.instance_variable_set(:@file_tail_bytes, tail.length)

        blob = stub_blob(blob_name, head + already_parsed + json_str1 + json_str2 + tail)

        allow(@azureblob_input).to receive(:register_for_read).and_return([blob, (head + already_parsed).length, nil])

        expect(@json_codec).to receive(:decode).with(head + json_str1 + tail).once.ordered
        expect(@json_codec).to receive(:decode).with(head + json_str2 + tail).once.ordered
        expect(@json_codec).to_not receive(:decode).ordered

        @azureblob_input.process(nil)
    end

    it "will update the registry offset when parsing JSON" do
        blob_name = "json_end_index"
        content = "{\"entity\":{ \"number\":42, \"string\":\"some string\" }},{},{\"a\":2} random text at the end"
        set_json_codec()

        blob = stub_blob(blob_name, content)

        registry_file_path = ""
        registry_offset = -1

        allow(@azureblob_input).to receive(:register_for_read).and_return([blob, 0, nil])
        allow(@json_codec).to receive(:decode).and_return([])

        expect(@azureblob_input).to receive(:update_registry) do |new_registry_item|
            registry_file_path = new_registry_item.file_path
            registry_offset = new_registry_item.offset
        end

        @azureblob_input.process(nil)

        expect(registry_file_path).to eq(blob_name)
        expect(registry_offset).to eq(content.length)
    end

    it "can output simple text" do
        blob_name = "basic_content"
        content = "some text\nmore text"

        blob = stub_blob(blob_name, content)

        allow(@azureblob_input).to receive(:register_for_read).and_return([blob, 0, nil])

        expect(@other_codec).to receive(:decode).with(content).ordered
        expect(@other_codec).to_not receive(:decode).ordered

        @azureblob_input.process(nil)
    end

    it "will add header and tail when the codec is not json" do
        blob_name = "head_tail_non_json"
        content = "{\"entity\":{ \"number\":42, \"string\":\"some string\" }}\n{\"entity2\":{ \"number2\":422, \"string2\":\"some other string\" }}"
        already_parsed = "{\"parsed_json\":true}"
        head = "{\"xyz\":42}{\"entities\" : \n["
        tail = "\n] }{\"abc\":42}\n"

        @azureblob_input.instance_variable_set(:@file_head_bytes, head.length)
        @azureblob_input.instance_variable_set(:@file_tail_bytes, tail.length)

        blob = stub_blob(blob_name, head + already_parsed + content + tail)

        allow(@azureblob_input).to receive(:register_for_read).and_return([blob, (head + already_parsed).length, nil])

        expect(@other_codec).to receive(:decode).with(head + content + tail).once.ordered
        expect(@other_codec).to_not receive(:decode).ordered

        @azureblob_input.process(nil)
    end

    it "will output content in chunks when the codec is not json" do
        blob_name = "chunked_content"
        #same size chunks
        chunk1 = "first chunk \n|"
        chunk2 = "second chunk \n"
        chunk3 = "third chunk \n|"
        smaller_chunk = "smaller\n"
        content = chunk1 + chunk2 + chunk3 + smaller_chunk

        blob = stub_blob(blob_name, content) 
        @azureblob_input.instance_variable_set(:@file_chunk_size_bytes, chunk1.length)

        allow(@azureblob_input).to receive(:register_for_read).and_return([blob, 0, nil])

        expect(@other_codec).to receive(:decode).with(chunk1).once.ordered
        expect(@other_codec).to receive(:decode).with(chunk2).once.ordered
        expect(@other_codec).to receive(:decode).with(chunk3).once.ordered
        expect(@other_codec).to receive(:decode).with(smaller_chunk).once.ordered
        expect(@other_codec).to_not receive(:decode).ordered

        @azureblob_input.process(nil)
    end

    it "will start from offset index when the codec is not json" do
        blob_name = "skip_start_index"
        already_parsed = "===="
        actual_content = "some text\nmore text"

        blob = stub_blob(blob_name,  already_parsed + actual_content)

        allow(@azureblob_input).to receive(:register_for_read).and_return([blob, already_parsed.length, nil])

        expect(@other_codec).to receive(:decode).with(actual_content).ordered
        expect(@other_codec).to_not receive(:decode).ordered

        @azureblob_input.process(nil)
    end

    it "will update the registry offset when the codec is not json" do
        blob_name = "non_json_end_index"
        content = "{\"entity\":{ \"number\":42, \"string\":\"some string\" }},{},{\"a\":2} random text at the end"

        blob = stub_blob(blob_name, content)

        registry_file_path = ""
        registry_offset = -1

        allow(@azureblob_input).to receive(:register_for_read).and_return([blob, 0, nil])
        allow(@other_codec).to receive(:decode).and_return([])

        expect(@azureblob_input).to receive(:update_registry) do |new_registry_item|
            registry_file_path = new_registry_item.file_path
            registry_offset = new_registry_item.offset
        end

        @azureblob_input.process(nil)

        expect(registry_file_path).to eq(blob_name)
        expect(registry_offset).to eq(content.length)
    end

    it "will update registry after n entries" do
        chunk_size = 5
        update_count = 3
        blob_name = "force_registry_offset"
        entries = [
            "first chunk \n",
            "second chunk",
            "third",
            "dgsdfgfgfg",
            "132435436",
            "dgsdfgfgfg"
        ]
        stub_const("LogStash::Inputs::LogstashInputAzureblob::UPDATE_REGISTRY_COUNT", update_count)

        content = ""
        entries.each do |entry|
            content << entry[0..chunk_size]
        end

        blob = stub_blob(blob_name, content)

        allow(@azureblob_input).to receive(:register_for_read).and_return([blob, 0, nil])
        @azureblob_input.instance_variable_set(:@file_chunk_size_bytes, chunk_size)
        allow(@other_codec).to receive(:decode).and_return([])

        update_registry_count = entries.length / update_count + 1
        expect(@azureblob_input).to receive(:update_registry).exactly(update_registry_count).times

        @azureblob_input.process(nil)
    end

    it "will update registry after n entries when the codec is json" do
        chunk_size = 5
        update_count = 3
        blob_name = "force_registry_offset_json"
        entries = [
            "{\"entity\":{ \"number\":42, \"string\":\"some string\" }}\n{\"entity2\":{ \"number2\":422, \"string2\":\"some other string\" }}",
            "invalid",
            "{\"val\":42}\n ",
            "{}",
            "{\"val}",
            "dgsdfgfgfg"
        ]
        set_json_codec()
        stub_const("LogStash::Inputs::LogstashInputAzureblob::UPDATE_REGISTRY_COUNT", update_count)

        content = ""
        entries.each do |entry|
            content << entry
        end

        blob = stub_blob(blob_name, content)

        allow(@azureblob_input).to receive(:register_for_read).and_return([blob, 0, nil])
        allow(@json_codec).to receive(:decode).and_return([])

        update_registry_count = entries.length / update_count + 1
        expect(@azureblob_input).to receive(:update_registry).exactly(update_registry_count).times

        @azureblob_input.process(nil)
    end

end