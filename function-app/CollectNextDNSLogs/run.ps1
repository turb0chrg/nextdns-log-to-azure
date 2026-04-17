param($Timer)

# Secrets are injected via Key Vault references in app settings; the Function App
# resolves them at runtime using its system-assigned managed identity.
$NextDNSApiKey    = $env:NEXTDNS_API_KEY
$WorkspaceId      = if ($env:LOG_ANALYTICS_WORKSPACE_CUSTOMER_ID) { $env:LOG_ANALYTICS_WORKSPACE_CUSTOMER_ID } else { $env:LOG_ANALYTICS_WORKSPACE_ID }
$WorkspaceKey     = $env:LOG_ANALYTICS_WORKSPACE_KEY
$LookbackMinutes  = [int]$env:LOOKBACK_MINUTES
$LogType          = 'NextDNS_CL'

# NextDNSLogCollector is auto-loaded from function-app/Modules/ by the Functions runtime.

Write-Host "Fetching all NextDNS profiles..."
$profiles = @(Get-NextDNSProfiles -ApiKey $NextDNSApiKey)
Write-Host "Retrieved $($profiles.Count) profile(s)."

$allLogs = @()
foreach ($profile in $profiles) {
    Write-Host "Pulling NextDNS logs for profile '$($profile.id)' over the last $LookbackMinutes minutes..."
    $logs = Get-NextDNSLogs -ApiKey $NextDNSApiKey -ProfileId $profile.id -LookbackMinutes $LookbackMinutes
    if ($logs) {
        Write-Host "Retrieved $($logs.Count) log entries from profile '$($profile.id)'."
        # Tag each log with the profile it came from
        foreach ($log in $logs) {
            $log | Add-Member -NotePropertyName "profileId" -NotePropertyValue $profile.id
            $log | Add-Member -NotePropertyName "profileName" -NotePropertyValue $profile.name
        }
        $allLogs += $logs
    } else {
        Write-Host "No logs retrieved from profile '$($profile.id)'."
    }
}

Write-Host "Total log entries across all profiles: $(@($allLogs).Count)"

if ($allLogs.Count -gt 0) {
    $flatLogs = $allLogs | ForEach-Object { ConvertTo-FlatLogEntry -Entry $_ -ProfileId $_.profileId -ProfileName $_.profileName }

    # Send in batches of 500 to stay well within the 30 MB Log Analytics payload limit.
    $batchSize = 500
    for ($i = 0; $i -lt $flatLogs.Count; $i += $batchSize) {
        $batch = $flatLogs[$i..[Math]::Min($i + $batchSize - 1, $flatLogs.Count - 1)]
        Send-ToLogAnalytics -WorkspaceId $WorkspaceId -WorkspaceKey $WorkspaceKey -LogType $LogType -Logs $batch
    }
} else {
    Write-Host "No logs to send."
}
