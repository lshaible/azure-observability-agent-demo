param(
  [string]$Subscription = $(az account show --query id -o tsv),
  [string]$ResourceGroup = "rg-obs-demo",
  [string]$Workspace = "law-obs-demo",
  [string]$Location = "westus2"
)
$ErrorActionPreference = "Stop"
$RG  = $ResourceGroup
$sub = $Subscription
az account set --subscription $sub | Out-Null
$LAWID = az monitor log-analytics workspace show -g $RG -n $Workspace --query id -o tsv

function QueryItem($title, $query, $viz, $size) {
  return @{
    type = 3
    name = "q-" + [guid]::NewGuid().ToString().Substring(0,8)
    content = @{
      version       = "KqlItem/1.0"
      query         = $query
      size          = $size
      title         = $title
      timeContext   = @{ durationMs = 1800000 }
      queryType     = 0
      resourceType  = "microsoft.operationalinsights/workspaces"
      crossComponentResources = @($LAWID)
      visualization = $viz
    }
  }
}
function TextItem($md) {
  return @{
    type = 1
    name = "t-" + [guid]::NewGuid().ToString().Substring(0,8)
    content = @{ version = "TextContent/1.0"; text = $md }
  }
}

$items = @(
  (TextItem "# Observability Demo Dashboard`nLive telemetry from **appi-obs-demo** (Flask app on App Service). All tiles query the Log Analytics workspace via KQL.")
  (QueryItem "Request volume (1-min)" "AppRequests | where TimeGenerated > ago(30m) | summarize Requests=count() by bin(TimeGenerated,1m), Name" "timechart" 0)
  (QueryItem "Failure rate %" "AppRequests | where TimeGenerated > ago(30m) | summarize Total=count(), Failed=countif(Success == `"False`") by bin(TimeGenerated,1m) | extend FailRatePct=round(100.0*Failed/Total,1) | project TimeGenerated, FailRatePct" "timechart" 0)
  (QueryItem "Latency by endpoint (P50/P95/P99 ms)" "AppRequests | where TimeGenerated > ago(30m) | summarize P50=round(percentile(DurationMs,50),0), P95=round(percentile(DurationMs,95),0), P99=round(percentile(DurationMs,99),0) by Name | order by P95 desc" "table" 0)
  (QueryItem "Requests by result code" "AppRequests | where TimeGenerated > ago(30m) | summarize Count=count() by ResultCode | order by Count desc" "piechart" 1)
  (QueryItem "Top exceptions" "AppExceptions | where TimeGenerated > ago(30m) | summarize Count=count() by ExceptionType, ProblemId | order by Count desc" "table" 1)
)

$serialized = (@{
  version = "Notebook/1.0"
  items   = $items
  isLocked = $false
  fallbackResourceIds = @($LAWID)
} | ConvertTo-Json -Depth 30 -Compress)

$wbGuid = [guid]::NewGuid().ToString()
$body = @{
  location   = $Location
  kind       = "shared"
  properties = @{
    displayName    = "Observability Demo Dashboard"
    serializedData = $serialized
    category       = "workbook"
    sourceId       = "Azure Monitor"
    version        = "Notebook/1.0"
  }
} | ConvertTo-Json -Depth 40

$bodyFile = Join-Path $PSScriptRoot "wb-body.json"
$body | Out-File -FilePath $bodyFile -Encoding utf8

$url = "https://management.azure.com/subscriptions/$sub/resourceGroups/$RG/providers/microsoft.insights/workbooks/$($wbGuid)?api-version=2022-04-01"
az rest --method put --uri $url --body "@$bodyFile" --headers "Content-Type=application/json" --query "{name:properties.displayName, id:id}" -o json
Write-Output "WORKBOOK_GUID: $wbGuid"
