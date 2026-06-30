# Security Policy

This is a **demo / educational** repository for the Azure Monitor Observability
Agent. It is not intended to run production workloads.

## Reporting a vulnerability

If you discover a security issue in this repository's code or scripts, please
**do not open a public issue**. Instead, use GitHub's private vulnerability
reporting:

1. Go to the **Security** tab of this repository.
2. Click **Report a vulnerability** to open a private security advisory.

Please include steps to reproduce, affected files, and any relevant context
(with credentials, tenant/subscription IDs, and other secrets redacted).

## Scope and good practices

- The demo reads its Application Insights connection string from an app setting
  (`APPLICATIONINSIGHTS_CONNECTION_STRING`) — **never** commit connection
  strings, instrumentation keys, tenant/subscription IDs, or other secrets.
- Instance-specific generated files (`appname.txt`, `wb-body.json`, `*.zip`,
  `.env`) are git-ignored; keep them out of commits.
- Tear down demo resources when finished (`az group delete -n <rg> --yes`) to
  avoid leaving exposed endpoints running.
