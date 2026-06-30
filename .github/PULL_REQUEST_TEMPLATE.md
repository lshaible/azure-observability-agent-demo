## Summary

<!-- What does this PR change and why? -->

## Type of change

- [ ] Bug fix
- [ ] New feature / enhancement
- [ ] Documentation
- [ ] Script / infrastructure change

## How was this tested?

<!-- e.g. ran deploy-all.ps1 end-to-end in a throwaway RG, ran PSScriptAnalyzer, etc. -->

## Checklist

- [ ] No secrets, tenant IDs, subscription IDs, or connection strings are committed
- [ ] Scripts remain parameterized (no hardcoded instance-specific values)
- [ ] `Invoke-ScriptAnalyzer -Path . -Recurse -Severity Warning,Error` passes (no errors)
- [ ] Updated `README.md` / `DEMO_GUIDE.md` if behavior changed
