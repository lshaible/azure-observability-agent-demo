<#
.SYNOPSIS
  Generates load (and errors) against the Observability demo web app.

.DESCRIPTION
  Continuously calls the demo app's endpoints to produce telemetry in Application Insights:
    GET /       -> 200 OK              (healthy requests)
    GET /slow   -> 200 (0.5-2s delay)  (latency)
    GET /error  -> 500 ValueError      (failures + exceptions)

  This is what feeds the alerts and the Azure Copilot Observability Agent.

.PARAMETER Url
  Base URL of the web app. Defaults to the demo app.

.PARAMETER Minutes
  How long to run. Default 60.

.PARAMETER ErrorEvery
  Hit /error on every Nth request. Lower = more errors. Default 4.

.PARAMETER SlowEvery
  Hit /slow on every Nth request. Default 3.

.PARAMETER DelayMs
  Pause between iterations in milliseconds. Default 1500.

.EXAMPLE
  .\generate-errors.ps1
  Run with defaults (60 min, ~25% error rate).

.EXAMPLE
  .\generate-errors.ps1 -Minutes 15 -ErrorEvery 2
  Run 15 min with a heavy (~50%) error rate.

.EXAMPLE
  .\generate-errors.ps1 -Url "https://my-other-app.azurewebsites.net"
  Target a different app.
#>
[CmdletBinding()]
param(
  [string]$Url        = "",
  [int]   $Minutes    = 60,
  [int]   $ErrorEvery = 4,
  [int]   $SlowEvery  = 3,
  [int]   $DelayMs    = 1500
)

$ErrorActionPreference = "SilentlyContinue"

# Resolve the target URL: explicit -Url wins; else use appname.txt (written by deploy-all.ps1);
# else fall back to the reference-instance app.
if ([string]::IsNullOrWhiteSpace($Url)) {
  $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
  $nameFile = Join-Path $scriptDir "appname.txt"
  if (Test-Path $nameFile) {
    $app = (Get-Content $nameFile -Raw).Trim()
    if ($app) { $Url = "https://$app.azurewebsites.net" }
  }
  if ([string]::IsNullOrWhiteSpace($Url)) { $Url = "https://web-obs-demo-80295.azurewebsites.net" }
}

$end = (Get-Date).AddMinutes($Minutes)

$ok = 0; $slow = 0; $err = 0; $n = 0

Write-Host "Generating load against $Url for $Minutes minute(s)..." -ForegroundColor Cyan
Write-Host "  /error every $ErrorEvery requests, /slow every $SlowEvery. Ctrl+C to stop.`n" -ForegroundColor DarkGray

while ((Get-Date) -lt $end) {
  $n++

  try { Invoke-WebRequest "$Url/" -UseBasicParsing -TimeoutSec 30 | Out-Null; $ok++ } catch {}

  if ($SlowEvery -gt 0 -and $n % $SlowEvery -eq 0) {
    try { Invoke-WebRequest "$Url/slow" -UseBasicParsing -TimeoutSec 30 | Out-Null; $slow++ } catch {}
  }

  if ($ErrorEvery -gt 0 -and $n % $ErrorEvery -eq 0) {
    try { Invoke-WebRequest "$Url/error" -UseBasicParsing -TimeoutSec 30 | Out-Null }
    catch { $err++ }   # /error returns 500, so it lands here -- that's expected
  }

  if ($n % 20 -eq 0) {
    Write-Host ("  [{0:HH:mm:ss}] sent={1}  ok={2}  slow={3}  errors={4}" -f (Get-Date), $n, $ok, $slow, $err)
  }

  Start-Sleep -Milliseconds $DelayMs
}

Write-Host "`nDone. Totals: requests=$n ok=$ok slow=$slow errors=$err" -ForegroundColor Green
Write-Host "Telemetry appears in Application Insights after ~2-4 min (ingestion lag)." -ForegroundColor DarkGray
