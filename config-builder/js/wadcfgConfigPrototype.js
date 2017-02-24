var wadcfgConfigPrototype = {
    
    // JSON public config prototype
    jsonPublic : `
{
    "WadCfg": {
        "DiagnosticMonitorConfiguration" : {
            "overallQuotaInMB": 4096,
            "useProxyServer": false,
            "eventVolume": "Small",
            "sinks": "",
            "Metrics": {
                "resourceId": "/SUBSCRIPTIONS/{subscriptionGuid}/RESOURCEGROUPS/{resourceGroupName}/PROVIDERS/Microsoft.Compute/virtualMachines/{vmName}",
                "MetricAggregation": [
                    {
                        "scheduledTransferPeriod": "PT1H"
                    }
                ]
            },
            "DiagnosticInfrastructureLogs": {
                "scheduledTransferLogLevelFilter": "Error",
                "sinks": ""
            },
            "Directories": {
                "scheduledTransferPeriod": "PT1M",
                "IISLogs": {
                    "containerName": "wad-iis-logfiles"
                },
                "FailedRequestLogs": {
                    "containerName": "wad-failedrequestlogs"
                },
                "DataSources": {
                    "DirectoryConfiguration": [
                        {
                            "containerName": "logcontainer",
                            "Absolute": {
                                "path": "c:\\logs",
                                "expandEnvironment": false
                            },
                            "LocalResource": {
                                "relativePath": "relativeDirToLocalResource",
                                "name": "localResourceName"
                            }
                        }
                    ]
                }
            },
            "PerformanceCounters": {
                "scheduledTransferPeriod": "PT1M",
                "sinks": "",
                "PerformanceCounterConfiguration": [
                    {
                        "counterSpecifier": "\\Processor(_Total)\\% Processor Time",
                        "sampleRate": "PT15S",
                        "unit": "Percent",
                        "annotation": [
                            {
                                "displayName": "CPU utilization",
                                "locale": "en-us"
                            }
                        ],
                        "sinks": ""
                    }
                ]
            },
            "WindowsEventLog": {
                "scheduledTransferPeriod": "PT1M",
                "sinks": "",
                "DataSource": [
                    {
                        "name": "Application!*[System[(Level = 1 or Level = 2)]]",
                        "sinks": ""
                    }
                ]
            },
            "EtwProviders": {
                "sinks": "",
                "EtwEventSourceProviderConfiguration": [
                    {
                        "scheduledTransferPeriod": "PT1M",
                        "scheduledTransferLogLevelFilter": "Verbose",
                        "provider": "EtwProviderName",
                        "scheduledTransferKeywordFilter": "0",
                        "sinks": "",
                        "Event": [
                            {
                                "id": 1,
                                "eventDestination": "EventDestination1",                        
                                "sinks": ""
                            }    
                        ],
                        "DefaultEvents": {
                            "eventDestination": "DefaultEventDestination",
                            "sinks": ""
                        }
                    }                
                ],
                "EtwManifestProviderConfiguration": [
                    {
                        "scheduledTransferPeriod": "PT1M",
                        "scheduledTransferLogLevelFilter": "Verbose",
                        "provider": "00000000-0000-0000-0000-000000000000",
                        "scheduledTransferKeywordFilter": "0",
                        "sinks": "",
                        "Event": [
                            {
                                "id": 1,
                                "eventDestination": "EventDestination1",                        
                                "sinks": ""
                            }    
                        ],
                        "DefaultEvents": {
                            "eventDestination": "DefaultEventDestination",
                            "sinks": ""
                        }
                    }                
                ]
            },
            "CrashDumps": {
                "directoryQuotaPercentage": 10,
                "dumpType": "Mini",
                "containerName": "myDumpContainer",
                "sinks": "",
                "CrashDumpConfiguration": [
                    {
                        "processName": "w3wp.exe",
                        "sinks": ""
                    }
                ]
            },
            "Logs": {
                "scheduledTransferPeriod": "PT1M",
                "scheduledTransferLogLevelFilter": "Error",
                "sinks": "",
                "Provider": {
                    "guid": "00000000-0000-0000-0000-000000000000"
                }
            }
        },
        "SinksConfig": {
            "Sink": [
                {
                    "name": "applicationInsights",
                    "ApplicationInsights": "00000000-0000-0000-0000-000000000000",
                    "EventHub": {
                        "Url": "https://myeventhub-ns.servicebus.windows.net/diageventhub",
                        "SharedAccessKeyName": "SendRule",
                        "usePublisherId": false
                    },
                    "StorageAccount": {
                        "name": "myAdditionalStorageAccount",
                        "endpoint": "https://core.windows.net"
                    },
                    "Channels": {
                        "Channel": [
                            {
                                "logLevel": "Error",
                                "name": "errors"
                            }
                        ]
                    }
                }
            ]
        }
    },
    "WadCfgBlob": {
        "containerName": "blobContainerName",
        "blobName": "blobNameWithWadCfg"
    },
    "StorageAccount": "diagstorageaccount",
    "StorageType": "TableAndBlob"
}
`.replace(/\\/g, "\\\\\\\\"), // Since this string will be fed through the JSON parser, all backslashes need to be escaped two more times

    // JSON private config prototype
    jsonPrivate : `
{
    "storageAccountName": "diagstorageaccount",
    "storageAccountKey": "{base64 encoded key}",
    "storageAccountEndPoint": "https://core.windows.net",
    "storageAccountSasToken": "{sas token}",
    "EventHub": {
        "Url": "https://myeventhub-ns.servicebus.windows.net/diageventhub",
        "SharedAccessKeyName": "SendRule",
        "SharedAccessKey": "{base64 encoded key}"
    },
    "SecondaryStorageAccounts": {
        "StorageAccount": [
            {
                "name": "secondarydiagstorageaccount",
                "key": "{base64 encoded key}",
                "endpoint": "https://core.windows.net",
                "sasToken": "{sas token}"
            }
        ]
    },
    "SecondaryEventHubs": {
        "EventHub": [
            {
                "Url": "https://myeventhub-ns.servicebus.windows.net/secondarydiageventhub",
                "SharedAccessKeyName": "SendRule",
                "SharedAccessKey": "{base64 encoded key}"
            }
        ]
    }
}
`.replace(/\\/g, "\\\\\\\\"), // Since this string will be fed through the JSON parser, all backslashes need to be escaped two more times

    // XML public config prototype
    xmlPublic : `
  <PublicConfig xmlns="http://schemas.microsoft.com/ServiceHosting/2010/10/DiagnosticsConfiguration">
    <WadCfg>
      <DiagnosticMonitorConfiguration overallQuotaInMB="4096" useProxyServer="false" eventVolume="Small" sinks="">
        <Metrics resourceId="/SUBSCRIPTIONS/{subscriptionGuid}/RESOURCEGROUPS/{resourceGroupName}/PROVIDERS/Microsoft.Compute/virtualMachines/{vmName}">
          <MetricAggregation scheduledTransferPeriod="PT1H" />
        </Metrics>
        <DiagnosticInfrastructureLogs scheduledTransferLogLevelFilter="Error" sinks="" />
        <Directories scheduledTransferPeriod="PT1M">
          <IISLogs containerName="wad-iis-logfiles" />
          <FailedRequestLogs containerName="wad-failedrequestlogs" />
          <DataSources>
            <DirectoryConfiguration containerName="logcontainer">
              <Absolute path="c:\\logs" expandEnvironment="false" />
              <LocalResource relativePath=".\\relativeDirToLocalResource" name="localResourceName" />
            </DirectoryConfiguration>
          </DataSources>
        </Directories>
        <PerformanceCounters scheduledTransferPeriod="PT1M" sinks="">
          <PerformanceCounterConfiguration counterSpecifier="\\Processor(_Total)\\% Processor Time" sampleRate="PT15S" unit="Percent" sinks="">
            <annotation displayName="CPU utilization" locale="en-us" />
          </PerformanceCounterConfiguration>
        </PerformanceCounters>
        <WindowsEventLog scheduledTransferPeriod="PT1M" sinks="">
          <DataSource name="Application!*[System[(Level = 1 or Level = 2)]]" sinks="" />
        </WindowsEventLog>
        <EtwProviders sinks="">
          <EtwEventSourceProviderConfiguration scheduledTransferPeriod="PT1M" scheduledTransferLogLevelFilter="Verbose" provider="EtwProviderName" scheduledTransferKeywordFilter="0" sinks="">
            <Event id="1" eventDestination="EventDestination1" sinks="" />
            <DefaultEvents eventDestination="DefaultEventDestination" sinks="" />
          </EtwEventSourceProviderConfiguration>
          <EtwManifestProviderConfiguration scheduledTransferPeriod="PT6M" scheduledTransferLogLevelFilter="Verbose" provider="00000000-0000-0000-0000-000000000000" scheduledTransferKeywordFilter="0" sinks="">
            <Event id="1" eventDestination="EventDestination1" sinks="" />
            <DefaultEvents eventDestination="DefaultEventDestination" sinks="" />
          </EtwManifestProviderConfiguration>
        </EtwProviders>
        <CrashDumps directoryQuotaPercentage="10" dumpType="Mini" containerName="wad-crashdumps1" sinks="">
          <CrashDumpConfiguration processName="w3wp.exe" sinks="" />
        </CrashDumps>
        <Logs scheduledTransferPeriod="PT1M" scheduledTransferLogLevelFilter="Error" sinks="">
          <Provider guid="00000000-0000-0000-0000-000000000000" />
        </Logs>
      </DiagnosticMonitorConfiguration>
      <SinksConfig>
        <Sink name="applicationInsights">
          <ApplicationInsights>00000000-0000-0000-0000-000000000000</ApplicationInsights>
          <EventHub Url="https://myeventhub-ns.servicebus.windows.net/diageventhub" SharedAccessKeyName="SendRule" usePublisherId="false" />
          <StorageAccount name="myAdditionalStorageAccount" endpoint="https://core.windows.net" />
          <Channels>
            <Channel logLevel="Error" name="errors" />
          </Channels>
        </Sink>
      </SinksConfig>
    </WadCfg>
    <WadCfgBlob containerName="blobContainerName" blobName="blobNameWithWadCfg" />
    <StorageAccount>diagstorageaccount</StorageAccount>
    <StorageType>TableAndBlob</StorageType>
  </PublicConfig>
`,
    
    // XML private config prototype
    xmlPrivate : `
  <PrivateConfig xmlns="http://schemas.microsoft.com/ServiceHosting/2010/10/DiagnosticsConfiguration">
    <StorageAccount name="diagstorageaccount" key="{base64 encoded key}" endpoint="https://core.windows.net" sasToken="{sas token}" />
    <EventHub Url="https://myeventhub-ns.servicebus.windows.net/diageventhub" SharedAccessKeyName="SendRule" SharedAccessKey="{base64 encoded key}" />
    <SecondaryStorageAccounts>
        <StorageAccount name="secondarydiagstorageaccount" key="{base64 encoded key}" endpoint="https://core.windows.net" sasToken="{sas token}" />
    </SecondaryStorageAccounts>
    <SecondaryEventHubs>
        <EventHub Url="https://myeventhub-ns.servicebus.windows.net/secondarydiageventhub" SharedAccessKeyName="SendRule" SharedAccessKey="{base64 encoded key}" />
    </SecondaryEventHubs>
  </PrivateConfig>
`,
    
    // A map for private config to map fields between json and xml
    privateFieldCustomMappings : [
        {
            "json" : "/storageAccountName",
            "xml" : "/StorageAccount/name"
        },
        {
            "json" : "/storageAccountKey",
            "xml" : "/StorageAccount/key"
        },
        {
            "json" : "/storageAccountEndPoint",
            "xml" : "/StorageAccount/endpoint"
        },
        {
            "json" : "/storageAccountSasToken",
            "xml" : "/StorageAccount/sasToken"
        },
        {
            "json" : "/EventHub/Url",
            "xml" : "/EventHub/Url"
        },
        {
            "json" : "/EventHub/SharedAccessKeyName",
            "xml" : "/EventHub/SharedAccessKeyName"
        },
        {
            "json" : "/EventHub/SharedAccessKey",
            "xml" : "/EventHub/SharedAccessKey"
        },
        {
            "json" : "/SecondaryStorageAccounts/StorageAccount",
            "xml" :  "/SecondaryStorageAccounts/StorageAccount"
        },
        {
            "json" : "/SecondaryStorageAccounts/StorageAccount/name",
            "xml" :  "/SecondaryStorageAccounts/StorageAccount/name"
        },
        {
            "json" : "/SecondaryStorageAccounts/StorageAccount/key",
            "xml" :  "/SecondaryStorageAccounts/StorageAccount/key"
        },
        {
            "json" : "/SecondaryStorageAccounts/StorageAccount/endpoint",
            "xml" :  "/SecondaryStorageAccounts/StorageAccount/endpoint"
        },
        {
            "json" : "/SecondaryEventHubs/EventHub",
            "xml" :  "/SecondaryEventHubs/EventHub"
        },
        {
            "json" : "/SecondaryEventHubs/EventHub/Url",
            "xml" :  "/SecondaryEventHubs/EventHub/Url"
        },
        {
            "json" : "/SecondaryEventHubs/EventHub/SharedAccessKeyName",
            "xml" :  "/SecondaryEventHubs/EventHub/SharedAccessKeyName"
        },
        {
            "json" : "/SecondaryEventHubs/EventHub/SharedAccessKey",
            "xml" :  "/SecondaryEventHubs/EventHub/SharedAccessKey"
        }
    ]
}
