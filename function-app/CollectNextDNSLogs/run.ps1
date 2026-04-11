param($Timer)

# Secrets are injected via Key Vault references in app settings; the Function App
# resolves them at runtime using its system-assigned managed identity.
$NextDNSApiKey    = $env:NEXTDNS_API_KEY
$NextDNSProfileId = $env:NEXTDNS_PROFILE_ID
$WorkspaceId      = $env:LOG_ANALYTICS_WORKSPACE_ID
$WorkspaceKey     = $env:LOG_ANALYTICS_WORKSPACE_KEY
$LookbackMinutes  = [int]$env:LOOKBACK_MINUTES
$LogType          = 'NextDNS_CL'

# NextDNSLogCollector is auto-loaded from function-app/Modules/ by the Functions runtime.

Write-Host "Pulling NextDNS logs for the last $LookbackMinutes minutes..."
$logs = Get-NextDNSLogs -ApiKey $NextDNSApiKey -ProfileId $NextDNSProfileId -LookbackMinutes $LookbackMinutes
Write-Host "Retrieved $($logs.Count) log entries."

$flatLogs = $logs | ForEach-Object { ConvertTo-FlatLogEntry -Entry $_ }

# Send in batches of 500 to stay well within the 30 MB Log Analytics payload limit.
$batchSize = 500
for ($i = 0; $i -lt $flatLogs.Count; $i += $batchSize) {
    $batch = $flatLogs[$i..[Math]::Min($i + $batchSize - 1, $flatLogs.Count - 1)]
    Send-ToLogAnalytics -WorkspaceId $WorkspaceId -WorkspaceKey $WorkspaceKey -LogType $LogType -Logs $batch
}
