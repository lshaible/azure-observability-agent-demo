# Contributing

Thanks for your interest in improving this demo! It's a teaching/demo artifact for the
Azure Monitor Observability Agent, so contributions that make it clearer, more portable, or
more reliable are very welcome.

## Ground rules

- **Never commit instance-specific or sensitive values.** No tenant IDs, subscription IDs,
  connection strings, instrumentation keys, emails, or principal IDs. Use placeholders
  (e.g. `<your-subscription-id>`) in docs and parameters in scripts.
- The following are intentionally git-ignored — don't add them back:
  `appname.txt`, `wb-body.json`, `alert-failure-rate.json`, `*.zip`, `.env`.
- Keep everything **parameterized** so the demo runs in *any* subscription. `deploy-all.ps1`
  is the source of truth for the deploy flow.

## Local checks before opening a PR

PowerShell scripts are linted with [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer):

```powershell
Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Warning,Error
```

Quick parse-check of a single script:

```powershell
$errs=$null
[System.Management.Automation.Language.Parser]::ParseFile("./deploy-all.ps1",[ref]$null,[ref]$errs) | Out-Null
if($errs){$errs|%{$_.Message}} else {"OK"}
```

The CI workflow (`.github/workflows/lint.yml`) runs the same PSScriptAnalyzer check on every
push and pull request.

## Pull requests

1. Fork and create a feature branch.
2. Make focused changes; update `DEMO_GUIDE.md` / `README.md` if behavior changes.
3. Run the lint check above.
4. Open a PR describing what changed and how you tested it.

## Reporting issues

Please include your Azure CLI version, region, and the exact command/output (with any IDs
redacted). Note that the Observability Agent is a **preview** feature — some behavior
(issue dedup, status/impact-time PATCH, agent-mode editing) is documented in the
Troubleshooting section of `DEMO_GUIDE.md`.
