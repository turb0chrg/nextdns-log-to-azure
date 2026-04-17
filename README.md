# nextdns-log-to-azure

Pulls DNS query logs from all [NextDNS profiles](https://nextdns.github.io/api/#profiles) via the NextDNS API on a schedule and ships them to an Azure Log Analytics workspace for querying, alerting, and long-term retention.

## Architecture

```
NextDNS API
    │
    ▼
Azure Function App (PowerShell 7.2, Consumption)
    │  Timer trigger — default every hour
    │  Managed identity → Key Vault (secrets resolved at runtime)
    ▼
Azure Log Analytics Workspace
    └── NextDNS_CL (custom log table)
```

**Resources deployed:**
| Resource | SKU |
|---|---|
| Log Analytics Workspace | PerGB2018, 30-day retention |
| App Service Plan | Y1 Consumption |
| Function App | PowerShell 7.2, Linux, system-assigned managed identity |
| Key Vault | Standard, RBAC enabled |
| Storage Account | Standard_LRS (runtime plumbing) |

Secrets (`NEXTDNS_API_KEY`, `LOG_ANALYTICS_WORKSPACE_KEY`) are stored in Key Vault. The Function App references them via `@Microsoft.KeyVault(...)` app settings and resolves them using its managed identity — the values are never stored in plain text in the app configuration.

## Repository structure

```
infra/
  main.bicep                          # Orchestrates all modules, role assignment
  deploy-keyvault.bicep
  deploy-log-analytics.bicep
  deploy-function-app.bicep
function-app/
  Modules/
    NextDNSLogCollector/
      NextDNSLogCollector.psm1        # Shared module: fetch, flatten, send
  CollectNextDNSLogs/
    function.json                     # Timer trigger definition
    run.ps1                           # Function entry point
  host.json
Send-NextDNSLogs.ps1                  # Local test script (imports shared module)
```

The shared logic (NextDNS pagination, response flattening, Log Analytics signing and POST) lives entirely in `NextDNSLogCollector.psm1`. Both `run.ps1` and `Send-NextDNSLogs.ps1` are thin entry points that import it. The Functions runtime auto-loads modules from `function-app/Modules/`; the local script imports by path.

## Prerequisites

- [Az PowerShell module](https://learn.microsoft.com/powershell/azure/install-az-ps) (`Install-Module -Name Az -Scope CurrentUser`)
- [Azure Functions Core Tools v4](https://learn.microsoft.com/azure/azure-functions/functions-run-local)
- PowerShell 7+
- A NextDNS account with an API key from [nextdns.io/account](https://nextdns.io/account)
- An Azure subscription and a resource group

## Deployment

### 1. Log in to Azure

```powershell
Connect-AzAccount
Set-AzContext -SubscriptionId "<your-subscription-id>"
```

### 2. Deploy the infrastructure

```powershell
$nextDnsApiKey = Read-Host "NextDNS API key"           -AsSecureString

New-AzResourceGroupDeployment `
  -ResourceGroupName    "<your-resource-group>" `
  -TemplateFile         infra/main.bicep `
  -functionAppName      "nextdns-func" `
  -appServicePlanName   "nextdns-plan" `
  -storageAccountName   "nextdnsstorage" `
  -workspaceName        "nextdns-logs" `
  -keyVaultName         "nextdns-kv" `
  -nextDnsApiKey        $nextDnsApiKey `
  -keyVaultSecretsOfficerObjectId "<your-aad-group-object-id>"
```

> Using `Read-Host -AsSecureString` avoids your secrets appearing in shell history.

> **Where to find the values:**
> - `nextDnsApiKey` — [nextdns.io/account](https://nextdns.io/account)
> - `keyVaultSecretsOfficerObjectId` — Azure AD group object ID for Key Vault administration (optional if not managing Key Vault yourself)

This single deployment:
1. Queries all NextDNS profiles automatically via the API (no profile ID configuration needed)
2. Creates the Key Vault and stores the secrets
3. Deploys the Function App with a system-assigned managed identity
4. Grants the identity `Key Vault Secrets User` on the vault

Optional parameters and their defaults:

| Parameter | Default | Description |
|---|---|---|
| `location` | resource group location | Azure region |
| `pricingTier` | `PerGB2018` | Log Analytics pricing tier |
| `lookbackMinutes` | `60` | Minutes of logs pulled per run |
| `timerSchedule` | `0 0 * * * *` | Cron expression for the timer trigger |

### 3. Publish the function code

```powershell
cd function-app
func azure functionapp publish nextdns-func
```

## Running locally

```powershell
.\Send-NextDNSLogs.ps1 `
  -NextDNSApiKey    "<your-nextdns-api-key>" `
  -WorkspaceId      "<your-log-analytics-workspace-id>" `
  -WorkspaceKey     "<your-log-analytics-workspace-key>" `
  -LookbackMinutes  60
```

The script automatically queries all your NextDNS profiles and collects logs from each.

## Log Analytics schema

Logs land in the `NextDNS_CL` table. The NextDNS API response is flattened before ingestion — nested fields under `device` are promoted to top-level columns, and the `reasons` array is serialized as a JSON string queryable via `parse_json()`.

| Column | Type | Description |
|---|---|---|
| `timestamp_t` | datetime | When the DNS query occurred |
| `domain_s` | string | Queried domain |
| `root_s` | string | Root domain |
| `tracker_s` | string | Tracker identifier (if applicable) |
| `encrypted_b` | bool | Whether the query used an encrypted protocol |
| `protocol_s` | string | Protocol (DNS-over-HTTPS, DNS-over-TLS, UDP, etc.) |
| `clientIp_s` | string | Client IP address |
| `client_s` | string | Client identifier |
| `status_s` | string | Query status (default, blocked, allowed, error) |
| `device_id_s` | string | Device identifier |
| `device_name_s` | string | Device name |
| `device_model_s` | string | Device model |
| `reasons_s` | string (JSON) | Array of block reasons `[{id, name}]` |

## Example KQL queries

```kql
// All queries in the last 24 hours
NextDNS_CL
| where TimeGenerated > ago(24h)
| project timestamp_t, domain_s, status_s, protocol_s, device_name_s, clientIp_s
| order by timestamp_t desc

// Top 10 blocked domains
NextDNS_CL
| where TimeGenerated > ago(24h) and status_s == "blocked"
| summarize count() by domain_s
| top 10 by count_

// Blocked queries with the reason that triggered the block
NextDNS_CL
| where TimeGenerated > ago(24h) and status_s == "blocked"
| extend reasons = parse_json(reasons_s)
| mv-expand reasons
| extend reason_name = tostring(reasons.name)
| project timestamp_t, domain_s, device_name_s, reason_name
| order by timestamp_t desc

// Query volume per device over the last 7 days
NextDNS_CL
| where TimeGenerated > ago(7d)
| summarize queries = count() by device_name_s, bin(TimeGenerated, 1h)
| render timechart
```

## Estimated monthly cost

For typical home or small-office usage (under 5 GB/month ingested) the cost is effectively **$0–$1/month**. Log Analytics ingestion at $2.76/GB is the only meaningful cost at higher volumes — the Function App and storage are negligible on the Consumption plan.

| Daily queries | Monthly ingestion | Est. cost |
|---|---|---|
| 10,000 | ~300 MB | ~$0 (free tier) |
| 50,000 | ~1.5 GB | ~$0 (free tier) |
| 200,000 | ~6 GB | ~$2.76 |
