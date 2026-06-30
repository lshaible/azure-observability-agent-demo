# Azure Copilot Observability Agent — Complete Demo Guide

> End-to-end demo of Azure Monitor observability, culminating in the **Azure Copilot
> Observability Agent** autonomously diagnosing a live failure.

---

## 1. TL;DR — What this demo shows

A small web app continuously emits telemetry (requests, traces, exceptions) into Azure
Monitor. We deliberately break one endpoint so it throws errors. Then we show **two ways**
to diagnose the problem:

| Approach | Who does the work | Effort |
|---|---|---|
| **Manual** | A human writes KQL, reads charts, builds a workbook, configures alerts | High — you must know the tables and query language |
| **Observability Agent** | An AI agent ingests the fired alert, correlates signals, opens an **Issue**, and runs an **Investigation** with explainable root-cause | Near zero — ask nothing, it runs autonomously |

The "wow" moment: the agent produces a root-cause analysis of the `ValueError`/HTTP 500s
**without a human writing a single query.**

---

## 1.5 Deploy from scratch in ANY subscription

The resource names and IDs in **Section 2** are from one **reference instance**. To stand up
your own copy in **any** tenant/subscription, use the bundled
**`deploy-all.ps1`** — it creates the entire backbone end-to-end: Log Analytics, Application
Insights, the instrumented Flask web app on App Service, the action group, both alerts
(metric + log, with the divide-by-zero fix), the Azure Monitor workspace, the Observability
Agent (autonomous) + role assignment, and the Workbook dashboard.

```powershell
az login                     # sign in
cd C:\Observability\obs-demo
.\deploy-all.ps1 -Subscription <your-sub-id> -NotifyEmail you@contoso.com
```

Parameters:

| Parameter | Default | Notes |
|---|---|---|
| `-Subscription` | *(required)* | Target subscription id or name |
| `-NotifyEmail` | *(required)* | Email for the action group |
| `-ResourceGroup` | `rg-obs-demo` | |
| `-WebLocation` | `westus2` | App Service region. ⚠️ See quota note below |
| `-MonitorLocation` | `eastus` | LA + App Insights + AMW + agent (agent & AMW must match) |
| `-Prefix` | `obs-demo` | Name prefix for all resources |

> ⚠️ **App Service quota gotcha:** some subscriptions have **0 App Service VM quota in
> `eastus`/`eastus2`** — even the Free **F1** SKU. If `deploy-all.ps1` fails creating the plan/web
> app, re-run with `-WebLocation centralus` (or `westus2`/`westeurope`). The monitoring
> resources can stay in `eastus`; only the web app needs the quota-friendly region.

When it finishes, the script prints a **resource inventory** (your equivalents of the
Section 2 values: app URL, App Insights appId, Log Analytics customerId, agent principalId,
Workbook GUID) and writes the new app name to `appname.txt` so the generator scripts target
the right app. Then drive traffic with `generate-errors.ps1` (Section 4.3).

To tear it all down: `az group delete -n <ResourceGroup> --yes --no-wait` (Section 10).

> The rest of this guide (Sections 2–11) describes the **reference instance**; substitute your
> own names/IDs from the deploy output wherever you see `web-obs-demo-80295`, `appi-obs-demo`,
> `law-obs-demo`, `amw-obs-demo`, `obsagent-demo`, or the GUIDs.

---

## 2. Environment / Resource Inventory

> These are the **reference instance** values (one concrete deployment). If you ran
> `deploy-all.ps1` (Section 1.5), use the inventory it printed instead.

|---|---|
| Tenant | `<your-tenant-guid>` |
| Subscription | `<your-subscription-guid>` |
| Resource group | `rg-obs-demo` |

| Resource | Name | Region | Purpose |
|---|---|---|---|
| Web App (Flask) | `web-obs-demo-80295` ⁽¹⁾ | westus2 | Emits telemetry; has the broken endpoint |
| App Service Plan | `plan-obs-demo` (F1 Free) | westus2 | Hosts the web app |
| Application Insights | `appi-obs-demo` | eastus | APM: requests, traces, exceptions |
| Log Analytics workspace | `law-obs-demo` | eastus | Stores all telemetry (KQL backend) |
| Azure Monitor workspace | `amw-obs-demo` | eastus | Stores agent-created **Issues** |
| Action group | `ag-obs-demo` | global | Email notifications |
| Metric alert | `alert-failed-requests` | global | Fires when failed requests > 5 / 5 min |
| Log-query alert | `alert-failure-rate` | global | Fires when failure rate > 20% / 5 min |
| Workbook | `Observability Demo Dashboard` | — | Manual dashboard (6 KQL tiles) |
| **Observability Agent** | `obsagent-demo` | eastus | **Autonomous AI diagnosis** |

> ⁽¹⁾ The web app's `-80295` suffix is a **random 5-digit number generated on every deploy**
> (`web-<prefix>-<random>`), because `*.azurewebsites.net` hostnames must be globally unique.
> Yours will differ. `deploy-all.ps1` prints the real name and saves it to `appname.txt`
> (the generator scripts read it automatically).

**App URL:** https://<your-web-app>.azurewebsites.net

**Useful IDs (for KQL / portal) — values from your own deployment:**
- App Insights appId: `<app-insights-app-id>`
- Log Analytics customerId (workspace GUID): `<workspace-guid>`
- Workbook GUID: `<workbook-guid>`
- Agent identity principalId: `<agent-principal-id>`

---

## 3. Architecture

```
                         (load generator: PowerShell loop on the demo machine)
                                   |  HTTP GET  /  /slow  /error
                                   v
                    +------------------------------+
                    |  Azure App Service (westus2) |
                    |  web-obs-demo-80295          |
                    |  Python Flask + gunicorn     |
                    |  OpenTelemetry instrumented  |
                    +---------------+--------------+
                                    | OTLP / App Insights connection string
                                    v
                    +------------------------------+
                    | Application Insights         |
                    | appi-obs-demo (eastus)       |
                    +---------------+--------------+
                                    | workspace-based
                                    v
                    +------------------------------+
                    | Log Analytics workspace      |
                    | law-obs-demo (eastus)        |
                    | Tables: AppRequests,         |
                    | AppExceptions, AppTraces ... |
                    +------+----------------+------+
                           |                |
              KQL / Workbook            Alert rules (metric + log)
                  (manual)                     |
                                               v
                                    +----------------------+
                                    | Action group         |
                                    | ag-obs-demo (email)  |
                                    +----------+-----------+
                                               | fired alerts
                                               v
                  +-------------------------------------------------+
                  | Azure Copilot Observability Agent  obsagent-demo|
                  |  - ingests fired alerts                         |
                  |  - correlates signals + App Insights telemetry  |
                  |  - AUTO creates Issue  -> stored in amw-obs-demo |
                  |  - AUTO runs Investigation (root-cause)         |
                  +-------------------------------------------------+
```

---

## 4. The application & how errors are generated

### 4.1 What the app is
A minimal **Python Flask** app (`app.py`) with three routes, deployed to App Service and
instrumented with **Azure Monitor OpenTelemetry** (`configure_azure_monitor()` plus an
explicit `FlaskInstrumentor().instrument_app(app)` — required to emit `AppRequests` under
gunicorn):

| Route | Behavior | Telemetry produced |
|---|---|---|
| `GET /` | Returns `200 OK` | Fast `AppRequests` row (~15 ms) |
| `GET /slow` | Sleeps 0.5–2.0 s, returns `200` | Slow `AppRequests` row (P95 ~1900 ms) |
| `GET /error` | Raises `ValueError` → `500` | Failed `AppRequests` + `AppExceptions` row |

The `/error` route is the **intentional bug** — it always raises an unhandled
`ValueError("Demo exception for App Insights")`.

### 4.2 Who/what generates the errors
**A PowerShell load generator running on the demo machine** (`generate-errors.ps1`, not a
real user). It repeatedly calls the three endpoints with `Invoke-WebRequest`. By default
every 4th request hits `/error`, guaranteeing a steady stream of HTTP 500s and `ValueError`
exceptions. This is what keeps the alerts firing and gives the agent something to diagnose.

### 4.3 How to start generating errors
Use the bundled script (preferred). Run on the demo machine (PowerShell):

```powershell
cd C:\Observability\obs-demo

# Default: 60 min, error every 4th request, slow every 5th
.\generate-errors.ps1

# Heavy errors for a punchy demo (every 2nd request = 500), 30 min
.\generate-errors.ps1 -Minutes 30 -ErrorEvery 2 -SlowEvery 3
```
Parameters: `-Url`, `-Minutes` (60), `-ErrorEvery` (4), `-SlowEvery` (5), `-DelayMs` (500).

**To stop generating errors:**
```powershell
.\stop-errors.ps1            # stops any running generator
.\stop-errors.ps1 -WhatIf   # preview what would be stopped
```

**Manual one-off error (for a single dramatic 500):**
```powershell
Invoke-WebRequest "https://web-obs-demo-80295.azurewebsites.net/error" -UseBasicParsing
```

> ⏱ **Ingestion lag:** telemetry takes ~2–4 minutes to appear in Azure Monitor. Always
> query with `ago(10m)` or wider, never `ago(1m)`.

---

## 5. Manual diagnosis (the "before" story)

This is how an engineer diagnoses the problem **without** the agent. Use it to set up the
contrast.

### 5.1 In the portal
1. Portal → **Log Analytics workspace** → `law-obs-demo` → **Logs**.
   (Use the *workspace* scope, not the App Insights → Logs blade — see the schema note below.)
2. Paste and run these KQL queries one at a time.

> **⚠️ Schema note — two table names for the same data.**
> The **Log Analytics workspace** (`law-obs-demo`) uses the *workspace* schema:
> `AppRequests`, `AppExceptions`, column `TimeGenerated`, and `Success` is a **string**
> (`"True"`/`"False"`). The **Application Insights → Logs** blade uses the *classic*
> schema: `requests`, `exceptions`, column `timestamp`, and `success` is a **bool**
> (`true`/`false`). Running an `AppRequests` query in the App Insights blade fails with
> *"Failed to resolve table or column expression named 'AppRequests'"*. The queries below
> use the **workspace** schema. For the classic equivalents, see Section 5.3.

**Health summary:**
```kql
AppRequests
| where TimeGenerated > ago(15m)
| summarize Total=count(), Failed=countif(Success == "False"),
            AvgMs=round(avg(DurationMs),0), P95=round(percentile(DurationMs,95),0)
| extend FailRatePct=round(100.0*Failed/Total,1)
```

**What's slow (latency by endpoint):**
```kql
AppRequests
| where TimeGenerated > ago(15m)
| summarize P95=round(percentile(DurationMs,95),0), Count=count() by Name
| order by P95 desc
```

**What's failing + the exception (root cause):**
```kql
AppRequests
| where TimeGenerated > ago(15m) and Success == "False"
| join kind=leftouter (
    AppExceptions | where TimeGenerated > ago(15m)
    | project OperationId, ExceptionType, Message
  ) on OperationId
| summarize Failures=count() by Name, ResultCode, ExceptionType
| order by Failures desc
```

**Failure-rate trend (chart):**
```kql
AppRequests
| where TimeGenerated > ago(30m)
| summarize Total=count(), Failed=countif(Success == "False") by bin(TimeGenerated, 1m)
| extend FailRatePct = round(100.0*Failed/Total, 1)
| render timechart
```

### 5.3 Classic schema (if running in App Insights → Logs)
If you prefer the **`appi-obs-demo` → Logs** blade, use the classic table/column names.
Health summary equivalent:
```kql
requests
| where timestamp > ago(15m)
| summarize Total=count(), Failed=countif(success == false),
            AvgMs=round(avg(duration),0), P95=round(percentile(duration,95),0)
| extend FailRatePct=round(100.0*Failed/Total,1)
```
Failure-rate trend equivalent:
```kql
requests
| where timestamp > ago(30m)
| summarize Total=count(), Failed=countif(success == false) by bin(timestamp, 1m)
| extend FailRatePct = round(100.0*Failed/Total, 1)
| render timechart
```
Mapping: `AppRequests`→`requests`, `AppExceptions`→`exceptions`, `TimeGenerated`→`timestamp`,
`DurationMs`→`duration`, `Success == "False"`→`success == false`.


### 5.2 The manual conclusion
"100% of failures are `GET /error` → 500, caused by a `ValueError`; `/slow` owns the
latency tail." **A human had to know the table names and write the KQL.**

### 5.3 The manual dashboard (Workbook)
Portal → **Monitor → Workbooks → Observability Demo Dashboard**. Six tiles (request
volume, failure rate %, latency P50/P95/P99, result-code pie, top exceptions). This is the
hand-built equivalent of what the agent produces automatically.

---

## 6. The Observability Agent (the "after" story)

### 6.1 What it is
**Azure Copilot Observability Agent** (`Microsoft.Monitor/observabilityAgents`) — an AI
agent that runs autonomously inside Azure Monitor. When an alert fires, it:
1. **Ingests** the fired alert and its context.
2. **Analyzes** the monitored Application Insights telemetry to build system knowledge.
3. **Correlates** related signals and **creates an Issue** (stored in the Azure Monitor workspace).
4. **Runs an Investigation** producing an explainable root-cause with the evidence it used.

Our agent `obsagent-demo` is configured with:
- **IssueCreation = Auto**, **Investigation = Auto**
- Monitoring `appi-obs-demo` (autonomous)
- Custom instruction: *"Create an issue when failed requests spike or the
  alert-failed-requests alert fires; correlate the 5xx on /error and investigate the
  ValueError."*

### 6.2 Example issue (captured in this environment) + what to do with Status

The agent created an Issue autonomously from the firing alert. Treat the details below as an
**illustrative example** — the exact **Issue id** changes every time a new issue is created
(e.g. this run produced `ae44de89-…`, a later run produced `549baabc-…`). Always look up the
current one in **Azure Monitor → Issues**.

- **Issue title:** `[appi-obs-demo] Failed requests spike detected on appi-obs-demo`
- **Issue id (example):** `ae44de89-3fef-4e1e-98cf-4f0f729d261e`
- **Severity:** Sev2 — **Status:** New
- **Agent's stated reason (background):** *"Observability agent created this issue for
  appi-obs-demo because failed requests spiked on Application Insights resource
  'appi-obs-demo', triggering the customer-defined failed-requests alert condition."*
- **Investigations:** 1 (auto-started). Open the Issue in the portal to read the
  root-cause analysis and the signals the agent considered.

**What to do with the Status field:**

| Context | How to use Status |
|---|---|
| **Real world** | Drive the issue through its lifecycle as the incident progresses: `New` → `In Progress` (someone's on it) → `Mitigated` → `Resolved` → `Closed`. The issue is the **shared coordination record** for handoffs; remediation happens outside the issue, then you mark it Resolved/Closed. Use `On-Hold`/`Canceled` for paused or invalid items. |
| **Demo** | Set Status to `Closed` on the existing issue when you want the agent to mint a **brand-new** issue for the next spike (the agent dedupes into an open issue otherwise). See **Section 6.5** for the close → re-trigger reset recipe. |

> Tip: an open (`New`/`In Progress`) issue absorbs new correlated spikes; a `Closed` issue
> does not — closing is what "resets" the demo so a fresh issue and investigation appear.


> Issues live under `Microsoft.Monitor/accounts/{amw}/issues` (api `2025-10-03-preview`).
> Investigations are surfaced inside the Issue in the portal.

### 6.3 How it was created (reproducible)
Prerequisites: an **Azure Monitor workspace** in the same region (`amw-obs-demo`), and the
agent's managed identity needs **Monitoring Contributor**.

ARM template: `obsagent.json` (in this folder). Deploy + role assignment:
```powershell
# Deploy the agent + monitored resource
az deployment group create -g rg-obs-demo -n obsagent-deploy `
  --template-file obsagent.json `
  --parameters agentName=obsagent-demo location=eastus `
    monitoringAccountId=<AMW resource id> `
    targetResourceId=<App Insights resource id> `
    monitoredResourceName=appi-obs-demo `
    issueCreationInstructions="Create an issue when failed requests spike..."

# Grant the agent identity permission to read alerts/telemetry + write issues
az role assignment create --assignee-object-id <agent principalId> `
  --assignee-principal-type ServicePrincipal `
  --role "Monitoring Contributor" --scope /subscriptions/<sub>
```

### 6.4 Portal create (alternative to ARM) — step by step
1. Search **"Observability Agents"** → **Create**.
2. **Details** tab:
   - Subscription: `<your-subscription>`
   - Resource group: `rg-obs-demo`
   - Name: `obsagent-demo`
   - Region: **East US** (must match the Azure Monitor workspace)
   - Azure Monitor workspace: `amw-obs-demo`
   - Identity: **System-assigned**
3. **Operations** tab:
   - Monitored application: `appi-obs-demo`
   - Allow agent to run autonomously: **On**
   - Correlation + issue creation: **On** (add custom instructions)
   - Investigation: **On**
   - Notifications: add `ag-obs-demo` (optional)
4. **Review + create** → **Create**.
5. **Post-create:** assign the agent's managed identity **Monitoring Contributor** at the
   subscription scope (Subscription → Access control (IAM) → Add role assignment).

### 6.5 Managing issue status — and resetting for a fresh issue
The agent **deduplicates**: while an issue for a given condition is still **open**, a new
spike of the *same* condition is correlated **into that existing issue** instead of creating
a new one. So if you re-run the error generator and *"don't see a new issue,"* it's because
the previous one is still open — this is correct AIOps behavior, not a bug.

**Change an issue's status** (portal):
1. **Azure Monitor → Issues** → open the issue.
2. On the **Overview** tab, use the **Status** dropdown: `New`, `In Progress`, `Mitigated`,
   `Resolved`, `Closed`, `Canceled`, or `On-Hold`.

> ⚠️ **Known preview bug:** updating **Status** or **Impact time** in the portal may fail with
> `BadRequest (400) Notification configuration cannot be updated`. When that happens, use the
> **API PATCH** below instead — it works reliably.

**To make the agent create a brand-new issue for the demo:**
1. Close the currently open issue — **Status → Closed** in the portal, or (if you hit the 400
   bug) the **API PATCH** below.
2. Re-trigger a spike: `.\generate-errors.ps1 -Minutes 30 -ErrorEvery 2`.
3. Wait for `alert-failed-requests` to fire again (~5–7 min), then the agent creates a
   **new** issue (~10–15 min total). It appears in **Azure Monitor → Issues**.

> API equivalents (handy when the portal Status/Impact-time UI misbehaves in preview):
> ```powershell
> $base = "https://management.azure.com/subscriptions/<sub>/resourceGroups/rg-obs-demo/providers/Microsoft.Monitor/accounts/amw-obs-demo/issues"
> $tok  = (az account get-access-token --resource https://management.azure.com --query accessToken -o tsv)
> # List issues
> Invoke-RestMethod "$base?api-version=2025-10-03-preview" -Headers @{Authorization="Bearer $tok"} |
>   ForEach-Object value | Select name, @{n='status';e={$_.properties.status}}, @{n='title';e={$_.properties.title}}
> # Close an issue (so a new one can be created)
> $body = @{ properties = @{ status = "Closed" } } | ConvertTo-Json
> Invoke-RestMethod -Method Patch -Uri "$base/<issueId>?api-version=2025-10-03-preview" `
>   -Headers @{Authorization="Bearer $tok"; 'Content-Type'='application/json'} -Body $body
> ```


---

## 7. Step-by-step live demo script (~12–15 min)

> Have two things open: the **Azure Portal** (signed into your tenant) and a
> terminal running the error generator (`.\generate-errors.ps1`).

### 7.0 Option: run with a "demo operator" (Copilot CLI)
Instead of typing commands yourself mid-demo, you can have **GitHub Copilot CLI** act as a
hands-free **demo operator** while you stay focused on the portal and narration. Open Copilot
CLI in `C:\Observability\obs-demo` and drive it with plain-English asks:

| You say to Copilot | What it does |
|---|---|
| "start errors" | Runs `.\generate-errors.ps1 -Minutes 30 -ErrorEvery 2` in the background |
| "stop errors" | Runs `.\stop-errors.ps1` |
| "close the issues" | API-PATCHes all open issues to `Closed` (works around the preview portal 400 bug) |
| "is the alert firing?" / "any new issue?" | Queries the Alerts / Issues API and reports status |
| "tell me when a new issue appears" | Polls the Issues API and notifies you when one is created |

Why this helps the demo:
- No alt-tabbing to a terminal; you keep the portal full-screen.
- It reliably closes issues via the API even when the portal Status/Impact-time UI returns the
  `400 Notification configuration cannot be updated` preview bug.
- It can watch for the alert→issue transition and cue you at the right moment.

> Prereq: signed in with `az login` to your subscription.
> All actions map to the same scripts/APIs documented in Sections 4.3, 6.5, and 9 — the
> operator is just a convenience layer, nothing magic.

### Act 0 — Setup (before audience arrives)
- Start the generator: `.\generate-errors.ps1 -Minutes 30 -ErrorEvery 2` so alerts fire.
- Confirm data: run the **health summary** KQL (Section 5.1); you should see a clear failure rate.
- Confirm the metric alert is **Fired**: Monitor → Alerts.

### Act 1 — Frame the problem (1 min)
"We have a web app. One endpoint is broken and throwing 500s. Let's diagnose it two ways."
Show the architecture diagram (Section 3).

### Act 2 — Show the live failure (1 min)
- Browser: open `https://web-obs-demo-80295.azurewebsites.net/` (OK), then `/error` (500).
- "That `/error` 500 is happening continuously under load."

### Act 3 — The MANUAL way (3–4 min)
- Portal → **Log Analytics workspace** `law-obs-demo` → **Logs** (workspace scope — see the
  schema note in Section 5.1).
- Run the four KQL queries (Section 5.1). Narrate: "I had to know `AppRequests` vs
  `AppExceptions` and write a join to find root cause."
- Optionally open the **Workbook** to show the hand-built dashboard.
- Punchline: "This works, but it requires KQL expertise and manual effort."

### Act 4 — The AGENT way (4–5 min) ★ the main event
1. Portal → search **Observability Agents** → open **`obsagent-demo`**.
2. Show **Overview**: autonomous operations enabled, monitoring `appi-obs-demo`.
3. Open the agent's **Issues** — note: **issues are NOT on the agent blade.** View them at
   **Azure Monitor → Issues** (all workspaces) or **Azure Monitor Workspace `amw-obs-demo`
   → Issues** (this AMW). Set the subscription filter to your subscription.
   - Show the **Issue** the agent auto-created from the fired alert.
   - Open it → show the **Investigation**: AI-generated root-cause naming the
     `ValueError`/500s on `/error`, the **signals it considered**, and **impact**.
4. Narrate the contrast: "No one wrote a query. The agent ingested the alert, correlated
   the telemetry, opened an issue, and investigated — autonomously, with explainable
   reasoning."

### Act 5 — Deep dive into the Issue (2–3 min)
Walk the audience through the Issue detail:
- **Title & summary** — plain-English description of the problem.
- **Timeline** — when it started, when the agent reacted.
- **Correlated alerts** — `alert-failed-requests` (and `alert-failure-rate`).
- **Investigation / root cause** — the `ValueError`, the failing endpoint, evidence rows.
- **Suggested next steps / impact** — what's affected and recommended action.
- **Explainability** — every conclusion references the signals used (governance/handover).

### Act 6 — Close (1 min)
"Same data. Manual = you write KQL and read charts. Agent = it reasons for you and hands
you a root-caused issue. That's the shift from *tools you operate* to an *agent that
operates for you*."

---

## 8. Talking points / FAQ

- **Why two alerts?** They demonstrate the **two Azure Monitor alert types**, which are not
  redundant — they answer different questions and have different mechanics:

  | | `alert-failed-requests` | `alert-failure-rate` |
  |---|---|---|
  | Type | **Metric** alert | **Log (scheduled query)** alert |
  | Signal | Pre-aggregated metric `requests/failed` | A **KQL query** over `AppRequests` |
  | Condition | Failed **count** > 5 / 5 min | Failure **rate %** > 20 / 5 min |
  | Scope | App Insights component `appi-obs-demo` | Log Analytics workspace `law-obs-demo` |
  | Strength | Cheap, fast, low-latency, simple thresholds | Flexible — any KQL (ratios, joins, custom fields) |

  *"Too many failures?"* (count/volume) vs *"too high a failure rate?"* (proportion) are
  genuinely different questions — 6 failures out of 6 requests vs out of 6,000 are very
  different situations.

- **Why do the two issues reference different resources?** Because the two alerts are **scoped
  to different resources** in the same telemetry chain
  (`web app → App Insights → Log Analytics`). The metric alert's issue is framed around
  `appi-obs-demo`; the log alert's investigation attributed impact to the web app
  `web-obs-demo-80295`. **Same root cause** (`ValueError` → 500 on `/error`), named after
  different rungs of the monitoring stack. This is a teaching point: it's exactly **why
  consistent alert scoping and agent-driven correlation matter** — otherwise one incident
  fragments into multiple issues.

- **What triggers the agent?** Fired alerts on the monitored resource. Our metric and log
  alerts fire from the `/error` traffic.
- **Where do issues live?** In the linked **Azure Monitor workspace** (`amw-obs-demo`).
- **Is it real-time?** No — allow a few minutes after an alert fires for the agent to
  correlate and create an issue, and a bit more for the investigation.
- **Does it need my KQL?** No. The agent writes its own analysis. The manual KQL in this
  guide is only for the "before" contrast.
- **Can a human stay in control?** Yes — Investigation can be set to **Manual** so a person
  decides when to run a deep investigation.
- **How do we show BOTH autonomous and manual with only one agent?** **Auto** mode doesn't
  *disable* the manual path — it just adds unattended behavior on top. The **Investigate**
  button is always available on any fired alert for a human to click. So one agent set to Auto
  gives you both: the agent acts on its own *and* you can still investigate manually. You'd
  only switch to **Manual** to *prove* the agent does nothing until a human asks — which
  removes the autonomous wow rather than adding to the manual story.
- **Is "autonomous vs manual" really just about the issue?** Yes. The agent's analysis
  (investigation/root-cause) is identical either way — the only difference is **who opens the
  issue**: **Auto** = the agent creates it unprompted; **Manual** = the investigation stays
  ephemeral until *you* click **Create issue** (and you can decline if it's benign/duplicate).
- **Why was the agent "associated" with only one of our two alerts?** The agent is tied to a
  **monitored resource** (`appi-obs-demo`), not to alerts directly. It autonomously acts on the
  alert scoped to that resource — `alert-failed-requests` (scoped to `appi-obs-demo`) → it
  auto-created an issue. `alert-failure-rate` is scoped to the **workspace** `law-obs-demo`
  (not the agent's monitored resource), so it produced **no** autonomous issue — but its
  **Investigate** button still worked for the manual path. To make the agent autonomously cover
  the rate signal too, re-scope that alert to `appi-obs-demo`, or add the workspace/web app as
  additional monitored resources.
- **Do I need the autonomous agent to investigate alerts?** No. Manual investigation is a
  **service capability** gated by (a) the subscription being associated with an **Azure Monitor
  Workspace** and (b) you having **Contributor / Monitoring Contributor / Issue Contributor**
  on that AMW. The deployed agent resource adds **unattended autonomy** on top of that
  always-available manual capability — it isn't required for the manual Investigate flow.
- **How do I change an existing agent's Auto/Manual mode?** The portal *edit* blade for an
  existing agent **does not expose the operation-mode toggles** (preview limitation) — only the
  *create* wizard shows them. Change `operations[].mode` via **API or ARM** instead. Quick API
  PATCH (set Investigation to Manual):
  ```powershell
  $tok = (az account get-access-token --resource https://management.azure.com --query accessToken -o tsv)
  $uri = "https://management.azure.com/subscriptions/<sub>/resourceGroups/rg-obs-demo/providers/Microsoft.Monitor/observabilityAgents/obsagent-demo?api-version=2026-05-01-preview"
  $a = Invoke-RestMethod -Uri $uri -Headers @{Authorization="Bearer $tok"}
  ($a.properties.operations | Where-Object type -eq 'Investigation').mode = 'Manual'  # or 'Auto'
  $body = @{ location=$a.location; identity=$a.identity; properties=$a.properties } | ConvertTo-Json -Depth 12
  Invoke-RestMethod -Method Put -Uri $uri -Headers @{Authorization="Bearer $tok"; 'Content-Type'='application/json'} -Body $body
  ```
  (Or re-deploy `obsagent.json` with the mode changed.) Modes: `Auto` = agent acts unprompted;
  `Manual` = waits for a human to trigger it.
- **Cost/limits?** Preview feature; 5 agents per subscription by default.

---

## 9. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| KQL returns nothing | Ingestion lag | Use `ago(10m)`+; wait 2–4 min |
| Workbook tiles empty | Time range / no data | Refresh; confirm the generator is running |
| No issue from agent | Alert hasn't fired yet, or < few min | Confirm alert is **Fired**; wait |
| Agent can't read data | Missing role | Ensure identity has **Monitoring Contributor** on the subscription |
| App returns 500 on `/` | Deploy/start issue | Check App Service → Log stream |
| `alert-failure-rate` never auto-resolves | Query divides by `count()`; no traffic → `count()=0` → **NaN**, read as "no data" so a Fired alert won't clear | Guard divide-by-zero: `iff(total==0, 0.0, 100.0*fails/total)` so no-traffic = `0.0` (resolves) |
| Failure rate always 0% / never fires on real failures | `Success==false` — `Success` is a **string** in `AppRequests` | Use `Success == "False"` |
| Duplicate issue not created on new spike | Agent dedupes while an equivalent issue is open | Close the open issue, then re-trigger errors |
| Can't change **Status or Impact time** on an issue (400 "Notification configuration cannot be updated") | Preview portal bug | Use the **API PATCH** (Section 6.5) to set status, e.g. `Closed`; or use the alert's **Investigate** button to start an investigation |
| Can't switch agent **IssueCreation/Investigation to Manual** in the portal | Preview limitation — the agent *edit* blade doesn't expose the operation-mode toggles (only the *create* wizard does) | Change `operations[].mode` via **API/ARM** (see FAQ + command below), not the portal |

**Confirm the alert is firing:**
```powershell
az rest --method get --uri "https://management.azure.com/subscriptions/$((az account show --query id -o tsv))/providers/Microsoft.AlertsManagement/alerts?api-version=2019-05-05-preview" `
  --query "value[?contains(id,'rg-obs-demo')].{rule:properties.essentials.alertRule, state:properties.essentials.monitorCondition}" -o table
```

**List agent-created issues:**
```powershell
$tok = az account get-access-token --resource https://management.azure.com --query accessToken -o tsv
Invoke-RestMethod -Method Get -Headers @{Authorization="Bearer $tok"} `
  -Uri "https://management.azure.com/subscriptions/$((az account show --query id -o tsv))/resourceGroups/rg-obs-demo/providers/Microsoft.Monitor/accounts/amw-obs-demo/issues?api-version=2025-10-03-preview" |
  Select-Object -ExpandProperty value
```

---

## 10. Cleanup

Deletes everything created for the demo:
```powershell
az group delete -n rg-obs-demo --yes --no-wait
```
(Also stop the generator if still running: `.\stop-errors.ps1`.)

---

## 11. File manifest (this folder)

| File | Purpose |
|---|---|
| `deploy-all.ps1` | **Deploys the entire demo from scratch in any subscription** (`-Subscription`, `-NotifyEmail`, `-WebLocation`, `-MonitorLocation`, `-Prefix`) |
| `app.py` | Flask app with `/`, `/slow`, `/error` |
| `requirements.txt` | Python deps (flask, gunicorn, azure-monitor-opentelemetry, otel-flask) |
| `workbook.ps1` | Builds/deploys the Workbook dashboard |
| `generate-errors.ps1` | Drives load + 500s/slow requests against the app (`-Minutes`, `-ErrorEvery`, `-SlowEvery`, `-DelayMs`) |
| `stop-errors.ps1` | Stops any running error/load generators (`-WhatIf`, `-ProcessId`) |
| `obsagent.json` | ARM template for the Observability Agent + monitored resource |
| `appname.txt` | The generated web app name |
| `DEMO_GUIDE.md` | This document |
