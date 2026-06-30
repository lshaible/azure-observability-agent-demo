<#
.SYNOPSIS
  Stops any running error/load generators started by generate-errors.ps1
  (or the older background load loops) against the obs-demo web app.

.DESCRIPTION
  Finds PowerShell processes whose command line references generate-errors.ps1,
  the demo URL, or the load-loop pattern, and stops them. Safe to run anytime;
  if nothing is running it just reports that.

.EXAMPLE
  .\stop-errors.ps1
  .\stop-errors.ps1 -WhatIf      # show what would be stopped without stopping
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$UrlMatch = "web-obs-demo",
    [int[]]$ProcessId = @()
)

$me = $PID  # don't kill ourselves

# Patterns that identify a running generator
$patterns = @(
    'generate-errors\.ps1',
    [regex]::Escape($UrlMatch),
    'loadloop',
    'Invoke-WebRequest.*\/error',
    'Invoke-RestMethod.*\/error'
)

Write-Host "Searching for running error/load generators..." -ForegroundColor Cyan

# Gather candidate PowerShell/pwsh processes with their command lines
$candidates = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
        $_.ProcessId -ne $me -and
        ($_.Name -match 'powershell|pwsh|python|curl') -and
        $_.CommandLine
    } |
    Where-Object {
        $cl = $_.CommandLine
        ($patterns | Where-Object { $cl -match $_ }).Count -gt 0
    }

# Allow explicit PIDs too
if ($ProcessId.Count -gt 0) {
    $extra = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $ProcessId -contains $_.ProcessId -and $_.ProcessId -ne $me }
    $candidates = @($candidates) + @($extra) | Sort-Object ProcessId -Unique
}

if (-not $candidates -or $candidates.Count -eq 0) {
    Write-Host "No running error/load generators found." -ForegroundColor Green
    return
}

Write-Host "Found $($candidates.Count) process(es):" -ForegroundColor Yellow
$candidates | ForEach-Object {
    $short = if ($_.CommandLine.Length -gt 120) { $_.CommandLine.Substring(0,120) + '...' } else { $_.CommandLine }
    Write-Host ("  PID {0}  {1}" -f $_.ProcessId, $short)
}

$stopped = 0
foreach ($p in $candidates) {
    if ($PSCmdlet.ShouldProcess("PID $($p.ProcessId)", "Stop-Process")) {
        try {
            Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
            Write-Host "  Stopped PID $($p.ProcessId)" -ForegroundColor Green
            $stopped++
        } catch {
            Write-Host "  Could not stop PID $($p.ProcessId): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

Write-Host ""
Write-Host "Done. Stopped $stopped process(es)." -ForegroundColor Cyan
Write-Host "Note: error/alert telemetry already ingested will persist; alerts auto-resolve once new failures stop (per their evaluation window)." -ForegroundColor DarkGray
