<#
.SYNOPSIS
  Deploys the COMPLETE Azure Copilot Observability Agent demo from scratch into ANY
  subscription: Log Analytics, Application Insights, an instrumented Flask web app on
  App Service, an action group, two alerts (metric + log), an Azure Monitor workspace,
  the Observability Agent (autonomous), and the Workbook dashboard.

.DESCRIPTION
  Idempotent-ish: uses `az ... create` which is safe to re-run. Prints a resource
  inventory at the end (the same values that Section 2 of DEMO_GUIDE.md lists for the
  reference instance).

.PARAMETER Subscription
  Subscription ID (or name) to deploy into. Required.

.PARAMETER ResourceGroup
  Resource group name. Default: rg-obs-demo

.PARAMETER WebLocation
  Region for the App Service plan + web app. IMPORTANT: some subscriptions have 0 App
  Service VM quota in eastus/eastus2 (even Free F1). Known-good: westus2, centralus,
  westeurope. Default: westus2

.PARAMETER MonitorLocation
  Region for Log Analytics, App Insights, Azure Monitor workspace, and the agent.
  The agent and the Azure Monitor workspace MUST be in the same region. Default: eastus

.PARAMETER Prefix
  Short name prefix for resources. Default: obs-demo

.PARAMETER NotifyEmail
  Email address for the action group. Required.

.EXAMPLE
  .\deploy-all.ps1 -Subscription <sub-id> -NotifyEmail you@contoso.com

.EXAMPLE
  .\deploy-all.ps1 -Subscription <sub-id> -WebLocation centralus -MonitorLocation westus2 `
    -Prefix obsdemo2 -NotifyEmail you@contoso.com
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Subscription,
    [string]$ResourceGroup = "rg-obs-demo",
    [string]$WebLocation = "westus2",
    [string]$MonitorLocation = "eastus",
    [string]$Prefix = "obs-demo",
    [Parameter(Mandatory = $true)][string]$NotifyEmail
)

$ErrorActionPreference = "Stop"
function Step($m) { Write-Host "`n=== $m ===" -ForegroundColor Cyan }

# Resource names
$law   = "law-$Prefix"
$appi  = "appi-$Prefix"
$plan  = "plan-$Prefix"
$rand  = Get-Random -Minimum 10000 -Maximum 99999
$web   = "web-$Prefix-$rand"
$ag    = "ag-$Prefix"
$amw   = "amw-$Prefix"
$agent = "obsagent-$Prefix"
$metricAlert = "alert-failed-requests"
$logAlert    = "alert-failure-rate"
$scriptDir   = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

Step "Selecting subscription $Subscription"
az account set --subscription $Subscription
$sub = az account show --query id -o tsv
Write-Host "Subscription: $sub"

Step "Resource group $ResourceGroup ($MonitorLocation)"
az group create -n $ResourceGroup -l $MonitorLocation -o none

Step "Log Analytics workspace $law"
az monitor log-analytics workspace create -g $ResourceGroup -n $law -l $MonitorLocation -o none
$lawId = az monitor log-analytics workspace show -g $ResourceGroup -n $law --query id -o tsv
$lawGuid = az monitor log-analytics workspace show -g $ResourceGroup -n $law --query customerId -o tsv

Step "Application Insights $appi (workspace-based)"
az monitor app-insights component create -g $ResourceGroup -a $appi -l $MonitorLocation `
    --workspace $lawId --kind web --application-type web -o none
$conn  = az monitor app-insights component show -g $ResourceGroup -a $appi --query connectionString -o tsv
$appId = az monitor app-insights component show -g $ResourceGroup -a $appi --query appId -o tsv
$appiId = az monitor app-insights component show -g $ResourceGroup -a $appi --query id -o tsv

Step "App Service plan $plan + web app $web ($WebLocation, Linux Python)"
Write-Host "  (If this fails with a quota error, retry with -WebLocation centralus or westeurope)" -ForegroundColor Yellow
az appservice plan create -g $ResourceGroup -n $plan -l $WebLocation --is-linux --sku F1 -o none
az webapp create -g $ResourceGroup -p $plan -n $web --runtime "PYTHON:3.11" -o none
az webapp config set -g $ResourceGroup -n $web `
    --startup-file "gunicorn --bind=0.0.0.0 --timeout 600 app:app" -o none
az webapp config appsettings set -g $ResourceGroup -n $web --settings `
    "APPLICATIONINSIGHTS_CONNECTION_STRING=$conn" "SCM_DO_BUILD_DURING_DEPLOYMENT=true" -o none

Step "Deploying Flask app code (app.py + requirements.txt)"
$zip = Join-Path $env:TEMP "obsdemo-app-$rand.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $scriptDir "app.py"), (Join-Path $scriptDir "requirements.txt") -DestinationPath $zip -Force
az webapp deploy -g $ResourceGroup -n $web --type zip --src-path $zip -o none
Write-Host "  App URL: https://$web.azurewebsites.net"

Step "Action group $ag (email $NotifyEmail)"
az monitor action-group create -g $ResourceGroup -n $ag --short-name obsdemo `
    --action email admin $NotifyEmail -o none
$agId = az monitor action-group show -g $ResourceGroup -n $ag --query id -o tsv

Step "Metric alert $metricAlert (failed requests > 5 / 5m)"
az monitor metrics alert create -g $ResourceGroup -n $metricAlert `
    --scopes $appiId `
    --condition "count requests/failed > 5" `
    --window-size 5m --evaluation-frequency 1m `
    --description "Failed requests spike on $appi" `
    --action $agId -o none

Step "Log alert $logAlert (failure rate > 20% / 5m)"
# NOTE: Success is a STRING in AppRequests ('True'/'False'); guard divide-by-zero so no
# traffic evaluates to 0.0 (below threshold) and the alert auto-resolves cleanly.
$logQuery = 'AppRequests | where TimeGenerated > ago(5m) | summarize total=count(), fails=countif(Success == "False") | extend FailRatePct = iff(total == 0, 0.0, 100.0*fails/total) | project FailRatePct'
az monitor scheduled-query create -g $ResourceGroup -n $logAlert `
    --scopes $lawId `
    --condition "max FailRatePct > 20" `
    --condition-query FailRatePct="$logQuery" `
    --window-size 5m --evaluation-frequency 5m `
    --auto-mitigate true `
    --description "Failure rate > 20% on $appi" `
    --action-groups $agId -o none

Step "Azure Monitor workspace $amw ($MonitorLocation)"
az resource create -g $ResourceGroup -n $amw `
    --resource-type "Microsoft.Monitor/accounts" `
    --properties '{}' -l $MonitorLocation -o none 2>$null
$amwId = az resource show -g $ResourceGroup -n $amw --resource-type "Microsoft.Monitor/accounts" --query id -o tsv

Step "Observability Agent $agent (ARM) + Monitoring Contributor"
$instructions = "Create an issue when failed requests on $appi spike or when the $metricAlert metric alert fires. Correlate 5xx failures on GET /error and investigate the ValueError exceptions."
az deployment group create -g $ResourceGroup -n "$agent-deploy" `
    --template-file (Join-Path $scriptDir "obsagent.json") `
    --parameters agentName=$agent location=$MonitorLocation `
        monitoringAccountId=$amwId targetResourceId=$appiId `
        monitoredResourceName=$appi `
        issueCreationInstructions="$instructions" -o none
$principalId = az deployment group show -g $ResourceGroup -n "$agent-deploy" --query properties.outputs.principalId.value -o tsv
Write-Host "  Agent identity principalId: $principalId"
az role assignment create --assignee-object-id $principalId --assignee-principal-type ServicePrincipal `
    --role "Monitoring Contributor" --scope "/subscriptions/$sub" -o none

Step "Workbook dashboard"
function QueryItem($title, $query, $viz, $size) {
    return @{ type = 3; name = "q-" + [guid]::NewGuid().ToString().Substring(0, 8)
        content = @{ version = "KqlItem/1.0"; query = $query; size = $size; title = $title
            timeContext = @{ durationMs = 1800000 }; queryType = 0
            resourceType = "microsoft.operationalinsights/workspaces"
            crossComponentResources = @($lawId); visualization = $viz } }
}
function TextItem($md) { return @{ type = 1; name = "t-" + [guid]::NewGuid().ToString().Substring(0, 8)
        content = @{ version = "TextContent/1.0"; text = $md } } }
$items = @(
    (TextItem "# Observability Demo Dashboard`nLive telemetry from **$appi**. All tiles query the Log Analytics workspace via KQL.")
    (QueryItem "Request volume (1-min)" "AppRequests | where TimeGenerated > ago(30m) | summarize Requests=count() by bin(TimeGenerated,1m), Name" "timechart" 0)
    (QueryItem "Failure rate %" "AppRequests | where TimeGenerated > ago(30m) | summarize Total=count(), Failed=countif(Success == `"False`") by bin(TimeGenerated,1m) | extend FailRatePct=round(100.0*Failed/Total,1) | project TimeGenerated, FailRatePct" "timechart" 0)
    (QueryItem "Latency by endpoint (P50/P95/P99 ms)" "AppRequests | where TimeGenerated > ago(30m) | summarize P50=round(percentile(DurationMs,50),0), P95=round(percentile(DurationMs,95),0), P99=round(percentile(DurationMs,99),0) by Name | order by P95 desc" "table" 0)
    (QueryItem "Requests by result code" "AppRequests | where TimeGenerated > ago(30m) | summarize Count=count() by ResultCode | order by Count desc" "piechart" 1)
    (QueryItem "Top exceptions" "AppExceptions | where TimeGenerated > ago(30m) | summarize Count=count() by ExceptionType, ProblemId | order by Count desc" "table" 1)
)
$serialized = (@{ version = "Notebook/1.0"; items = $items; isLocked = $false; fallbackResourceIds = @($lawId) } | ConvertTo-Json -Depth 30 -Compress)
$wbGuid = [guid]::NewGuid().ToString()
$wbBody = @{ location = $WebLocation; kind = "shared"
    properties = @{ displayName = "Observability Demo Dashboard"; serializedData = $serialized
        category = "workbook"; sourceId = "Azure Monitor"; version = "Notebook/1.0" } } | ConvertTo-Json -Depth 40
$wbFile = Join-Path $env:TEMP "wb-body-$rand.json"
$wbBody | Out-File -FilePath $wbFile -Encoding utf8
$wbUrl = "https://management.azure.com/subscriptions/$sub/resourceGroups/$ResourceGroup/providers/microsoft.insights/workbooks/$($wbGuid)?api-version=2022-04-01"
az rest --method put --uri $wbUrl --body "@$wbFile" --headers "Content-Type=application/json" -o none

# Persist the app name for the generator scripts
Set-Content -Path (Join-Path $scriptDir "appname.txt") -Value $web

Step "DONE — Resource inventory"
[pscustomobject]@{
    Subscription        = $sub
    ResourceGroup       = $ResourceGroup
    WebApp              = "$web ($WebLocation)"
    AppUrl              = "https://$web.azurewebsites.net"
    LogAnalytics        = "$law  customerId=$lawGuid"
    AppInsights         = "$appi  appId=$appId"
    ActionGroup         = $ag
    MetricAlert         = $metricAlert
    LogAlert            = $logAlert
    AzureMonitorWS      = $amw
    ObservabilityAgent  = "$agent  principalId=$principalId"
    WorkbookGuid        = $wbGuid
} | Format-List

Write-Host "`nNext: generate traffic ->  .\generate-errors.ps1 -Url https://$web.azurewebsites.net -Minutes 30 -ErrorEvery 2" -ForegroundColor Green
Write-Host "Telemetry has a 2-4 min ingestion lag. Alerts fire ~5-7 min after errors start; the agent creates an Issue ~10-15 min in." -ForegroundColor DarkGray
