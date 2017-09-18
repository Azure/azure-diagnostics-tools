# Logstash input plugin for Azure diagnostics data from Storage Tables 

## Summary
This plugin reads Azure diagnostics data from specified Azure Storage Table and parses the data for output.

## Installation
You can install this plugin using the Logstash "plugin" or "logstash-plugin" (for newer versions of Logstash) command:
```sh
logstash-plugin install logstash-input-azurewadtable
```
For more information, see Logstash reference [Working with plugins](https://www.elastic.co/guide/en/logstash/current/working-with-plugins.html).

## Configuration
### Required Parameters
__*account_name*__

The Azure Storage account name.

__*access_key*__

The access key to the storage account.

__*table_name*__

The storage table to pull data from.

### Optional Parameters
__*entity_count_to_process*__

The plugin queries and processes table entities in a loop, this parameter is to specify the maximum number of entities it should query and process per loop. The default value is 100.

__*collection_start_time_utc*__

Specifies the point of time after which the entities created should be included in the query results. The default value is when the plugin gets initialized:

```ruby
Time.now.utc.iso8601
```
__*etw_pretty_print*__

True to pretty print ETW files, otherwise False. The default value is False.

__*idle_delay_seconds*__

Specifies the seconds to wait between each processing loop. The default value is 15.  

__*endpoint*__

Specifies the endpoint of Azure environment. The default value is "core.windows.net".  

__*past_queries_count*__
Specifies the number of past queries to run so the plugin doesn't miss late arriving data. By default this is 5

### Examples
```
input
{
    azurewadtable
    {
        account_name => "mystorageaccount"
        access_key => "VGhpcyBpcyBhIGZha2Uga2V5Lg=="
        table_name => "WADWindowsEventLogsTable"
    }
}
```

## More information
The source code of this plugin is hosted in GitHub repo [Microsoft Azure Diagnostics with ELK](https://github.com/Azure/azure-diagnostics-tools). We welcome you to provide feedback and/or contribute to the project.

Please also see [Analyze Diagnostics Data with ELK template](https://github.com/Azure/azure-quickstart-templates/tree/master/diagnostics-with-elk) for quick deployment of ELK to Azure.   
