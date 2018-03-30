#r "System.Configuration"

using System;
using System.Configuration;
using Elasticsearch.Net;
using Nest;
using Nest.JsonNetSerializer;

public static async Task Run(string myEventHubMessage, TraceWriter log)
{
    await SendEventToElasticSearch(myEventHubMessage, log);
}

// Required application setting - target Elastic Search endpoint.
private const string Setting_Es_Uri = "es_uri";

// Required application setting - username for writing to ES.
private const string Setting_Es_Username = "es_username";

// Required application setting - password for writing to ES.
private const string Setting_Es_Password = "es_password";

// Optional application setting - ES index name prefix.
private const string Setting_Es_Index_Name_Prefix = "es_index_name_prefix";

private const string Error_Es_Uri_Missing = "Setting \"" + Setting_Es_Uri + "\" is missing.";
private const string Error_Es_Username_Missing = "Setting \"" + Setting_Es_Username + "\" is missing.";
private const string Error_Es_Password_Missing = "Setting \"" + Setting_Es_Password + "\" is missing.";
private const string DefaultIndexNamePrefix = "wadeventhub";
private const string EventDocumentTypeName = "event";

// Caches the last index name used so we don't have to do the check each time before sending data to ES.
private static string LastIndexName = null;

private static async Task SendEventToElasticSearch(string myEventHubMessage, TraceWriter log)
{
    string esUri = ConfigurationManager.AppSettings[Setting_Es_Uri];
    string username = ConfigurationManager.AppSettings[Setting_Es_Username];
    string password = ConfigurationManager.AppSettings[Setting_Es_Password];
    string indexNamePrefix = ConfigurationManager.AppSettings[Setting_Es_Index_Name_Prefix];

    if (string.IsNullOrWhiteSpace(esUri))
    {
        ReportError(log, Error_Es_Uri_Missing, throwException: true);
    }

    if (string.IsNullOrWhiteSpace(username))
    {
        ReportError(log, Error_Es_Username_Missing, throwException: true);
    }

    if (string.IsNullOrWhiteSpace(password))
    {
        ReportError(log, Error_Es_Password_Missing, throwException: true);
    }

    if (string.IsNullOrWhiteSpace(indexNamePrefix))
    {
        log.Warning($"Setting \"{Setting_Es_Index_Name_Prefix}\" not specified, using default value \"{DefaultIndexNamePrefix}\".");
        indexNamePrefix = DefaultIndexNamePrefix;
    }

    log.Verbose($"Sending Event Hub data to ElasticSearch at {esUri} ...");

    var pool = new SingleNodeConnectionPool(new Uri(esUri));
    var connectionSettings = new ConnectionSettings(pool, sourceSerializer: JsonNetSerializer.Default).BasicAuthentication(username, password);
    var client = new ElasticClient(connectionSettings);

    string currentIndexName = GetIndexName(indexNamePrefix);

    if (!string.Equals(LastIndexName, currentIndexName, StringComparison.Ordinal))
    {
        await EnsureIndexExists(currentIndexName, client, log);
        LastIndexName = currentIndexName;
    }

    var result = client.LowLevel.Index<BytesResponse>(currentIndexName, EventDocumentTypeName, myEventHubMessage);

    if (result.Success)
    {
        log.Info("Data successfully sent.");
        var body = System.Text.Encoding.Default.GetString(result.Body);
        log.Verbose(body);
    }
    else
    {
        ReportError(log, $"Failed to send data.{Environment.NewLine}{result.DebugInformation}", throwException: true);
    }
}

/// <summary>
/// Generates an index name.
/// </summary>
/// <param name="indexNamePrefix">Specifies a string prefix of the index name.</param>
/// <returns>An index name in the form of &lt;prefix&gt;-YYYY.MM.DD.</returns>
private static string GetIndexName(string indexNamePrefix)
{
    DateTimeOffset now = DateTimeOffset.UtcNow;
    string retval = $"{indexNamePrefix}-{now.Year.ToString("0000")}.{now.Month.ToString("00")}.{now.Day.ToString("00")}";
    return retval;
}

/// <summary>
/// Makes sure the specified index name has been created.
/// </summary>
/// <param name="currentIndexName">The index name to check.</param>
/// <param name="esClient">An Elastic client instance.</param>
/// <param name="log">A Trace writer instance.</param>
/// <returns>A Task representing the async operation.</returns>
private static async Task EnsureIndexExists(string currentIndexName, ElasticClient esClient, TraceWriter log)
{
    IExistsResponse existsResult = await esClient.IndexExistsAsync(currentIndexName);
    if (!existsResult.IsValid)
    {
        ReportError(log, $"Index exists check failed.{Environment.NewLine}{existsResult.DebugInformation}", throwException: true);
    }
    if (existsResult.Exists)
    {
        log.Info(currentIndexName + " - Index Exists.");
        return;
    }

    // TODO: allow the consumer to fine-tune index settings 
    IndexState indexState = new IndexState();
    indexState.Settings = new IndexSettings();
    indexState.Settings.NumberOfReplicas = 1;
    indexState.Settings.NumberOfShards = 5;
    indexState.Settings.Add("refresh_interval", "15s");


    ICreateIndexResponse createIndexResult = await esClient.CreateIndexAsync(currentIndexName, c => c.InitializeUsing(indexState));

    if (!createIndexResult.IsValid)
    {
        if (string.Equals(createIndexResult.ServerError?.Error?.Type, "IndexAlreadyExistsException", StringComparison.OrdinalIgnoreCase))
        {
            // This is fine, someone just beat us to create a new index. 
            return;
        }

        ReportError(log, $"Create index failed.{Environment.NewLine}{createIndexResult.DebugInformation}", throwException: true);
    }
}

private static void ReportError(TraceWriter log, string errorMessage, bool throwException)
{
    log.Error(errorMessage);

    if (throwException)
    {
        throw new ApplicationException(errorMessage);
    }
}
