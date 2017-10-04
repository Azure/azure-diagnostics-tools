# Logstash input plugin for Azure Storage Blobs

## Summary
This plugin reads and parses data from Azure Storage Blobs.

## Installation
You can install this plugin using the Logstash "plugin" or "logstash-plugin" (for newer versions of Logstash) command:
```sh
logstash-plugin install logstash-input-azureblob
```
For more information, see Logstash reference [Working with plugins](https://www.elastic.co/guide/en/logstash/current/working-with-plugins.html).

## Configuration
### Required Parameters
__*storage_account_name*__

The storage account name.

__*storage_access_key*__

The access key to the storage account.

__*container*__

The blob container name.

### Optional Parameters
__*endpoint*__

Specifies the endpoint of Azure Service Management. The default value is `core.windows.net`. 

__*registry_path*__

Specifies the file path for the registry file to record offsets and coordinate between multiple clients. The default value is `data/registry`.

Overwrite this value when there happen to be a file at the path of `data/registry` in the azure blob container.

__*interval*__

Set how many seconds to idle before checking for new logs. The default, `30`, means idle for `30` seconds.

__*registry_create_policy*__

Specifies the way to initially set offset for existing blob files.

This option only applies for registry creation. 

Valid values include:

  - resume
  - start_over

The default, `resume`, means when the registry is initially created, it assumes all blob has been consumed and it will start to pick up any new content in the blobs.

When set to `start_over`, it assumes none of the blob is consumed and it will read all blob files from begining.

Offsets will be picked up from registry file whenever it exists.

__*file_head_bytes*__

Specifies the header of the file in bytes that does not repeat over records. Usually, these are json opening tags. The default value is `0`.

__*file_tail_bytes*__
  
Specifies the tail of the file that does not repeat over records. Usually, these are json closing tags. The defaul tvalue is `0`.

### Advanced tweaking parameters

Keep these parameters default to use under normal situration. Tweak these parameters when dealing with large scale azure blobs and logs.

__*blob_list_page_size*__

Specifies the page-size for returned blob items. Too big number will hit heap overflow; Too small number will leads to too many requests. The default of `100` is good for heap size of 1G.

__*file_chunk_size_bytes*__

Specifies the buffer size used to download the blob content. This is also the maximum buffer size that will be passed to a codec except for JSON. The JSON codec will only receive valid JSON that might span between multiple chunks. Any malformed JSON content will be skipped.

The default value is 4194304 (4MB)

### Examples

* Bare-bone settings:

```yaml
input
{
    azureblob
    {
        storage_account_name => "mystorageaccount"
        storage_access_key => "VGhpcyBpcyBhIGZha2Uga2V5Lg=="
        container => "mycontainer"
    }
}
```

* Example for Wad-IIS

```yaml
input {
    azureblob
    {
        storage_account_name => 'mystorageaccount'
        storage_access_key => 'VGhpcyBpcyBhIGZha2Uga2V5Lg=='
        container => 'wad-iis-logfiles'
        codec => line
    }
}    
filter {
  ## Ignore the comments that IIS will add to the start of the W3C logs
  #
  if [message] =~ "^#" {
    drop {}
  }

  grok {
      # https://grokdebug.herokuapp.com/
      match => ["message", "%{TIMESTAMP_ISO8601:log_timestamp} %{WORD:sitename} %{WORD:computername} %{IP:server_ip} %{WORD:method} %{URIPATH:uriStem} %{NOTSPACE:uriQuery} %{NUMBER:port} %{NOTSPACE:username} %{IPORHOST:clientIP} %{NOTSPACE:protocolVersion} %{NOTSPACE:userAgent} %{NOTSPACE:cookie} %{NOTSPACE:referer} %{NOTSPACE:requestHost} %{NUMBER:response} %{NUMBER:subresponse} %{NUMBER:win32response} %{NUMBER:bytesSent} %{NUMBER:bytesReceived} %{NUMBER:timetaken}"]
  }

  ## Set the Event Timesteamp from the log
  #
  date {
    match => [ "log_timestamp", "YYYY-MM-dd HH:mm:ss" ]
      timezone => "Etc/UTC"
  }

  ## If the log record has a value for 'bytesSent', then add a new field
  #   to the event that converts it to kilobytes
  #
  if [bytesSent] {
    ruby {
      code => "event.set('kilobytesSent', event.get('bytesSent').to_i / 1024.0)"
    }
  }

  ## Do the same conversion for the bytes received value
  #
  if [bytesReceived] {
    ruby {
      code => "event.set('kilobytesReceived', event.get('bytesReceived').to_i / 1024.0 )"
    }
  }

  ## Perform some mutations on the records to prep them for Elastic
  #
  mutate {
    ## Convert some fields from strings to integers
    #
    convert => ["bytesSent", "integer"]
    convert => ["bytesReceived", "integer"]
    convert => ["timetaken", "integer"]

    ## Create a new field for the reverse DNS lookup below
    #
    add_field => { "clientHostname" => "%{clientIP}" }

    ## Finally remove the original log_timestamp field since the event will
    #   have the proper date on it
    #
    remove_field => [ "log_timestamp"]
  }

  ## Do a reverse lookup on the client IP to get their hostname.
  #
  dns {
    ## Now that we've copied the clientIP into a new field we can
    #   simply replace it here using a reverse lookup
    #
    action => "replace"
    reverse => ["clientHostname"]
  }

  ## Parse out the user agent
  #
  useragent {
    source=> "useragent"
    prefix=> "browser"
  }
}
output {
    file {
        path => '/var/tmp/logstash-file-output'
        codec => rubydebug
    }
    stdout { 
        codec => rubydebug
    }
}
```

* NSG Logs

```yaml
input {
   azureblob
     {
         storage_account_name => "mystorageaccount"
         storage_access_key => "VGhpcyBpcyBhIGZha2Uga2V5Lg=="
         container => "insights-logs-networksecuritygroupflowevent"
         codec => "json"
         # Refer https://docs.microsoft.com/en-us/azure/network-watcher/network-watcher-read-nsg-flow-logs
         # Typical numbers could be 21/9 or 12/2 depends on the nsg log file types
         file_head_bytes => 21
         file_tail_bytes => 9
     }
   }

   filter {
     split { field => "[records]" }
     split { field => "[records][properties][flows]"}
     split { field => "[records][properties][flows][flows]"}
     split { field => "[records][properties][flows][flows][flowTuples]"}

  mutate{
   split => { "[records][resourceId]" => "/"}
   add_field => {"Subscription" => "%{[records][resourceId][2]}"
                 "ResourceGroup" => "%{[records][resourceId][4]}"
                 "NetworkSecurityGroup" => "%{[records][resourceId][8]}"}
   convert => {"Subscription" => "string"}
   convert => {"ResourceGroup" => "string"}
   convert => {"NetworkSecurityGroup" => "string"}
   split => { "[records][properties][flows][flows][flowTuples]" => ","}
   add_field => {
               "unixtimestamp" => "%{[records][properties][flows][flows][flowTuples][0]}"
               "srcIp" => "%{[records][properties][flows][flows][flowTuples][1]}"
               "destIp" => "%{[records][properties][flows][flows][flowTuples][2]}"
               "srcPort" => "%{[records][properties][flows][flows][flowTuples][3]}"
               "destPort" => "%{[records][properties][flows][flows][flowTuples][4]}"
               "protocol" => "%{[records][properties][flows][flows][flowTuples][5]}"
               "trafficflow" => "%{[records][properties][flows][flows][flowTuples][6]}"
               "traffic" => "%{[records][properties][flows][flows][flowTuples][7]}"
                }
   convert => {"unixtimestamp" => "integer"}
   convert => {"srcPort" => "integer"}
   convert => {"destPort" => "integer"}        
  }

  date{
    match => ["unixtimestamp" , "UNIX"]
  }
 }

 output {
   stdout { codec => rubydebug }
 } 
```

## More information
The source code of this plugin is hosted in GitHub repo [Microsoft Azure Diagnostics with ELK](https://github.com/Azure/azure-diagnostics-tools). We welcome you to provide feedback and/or contribute to the project.