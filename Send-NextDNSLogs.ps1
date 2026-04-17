#Requires -Version 7.0
<#
.SYNOPSIS
    Pulls logs from all NextDNS profiles via the API and sends them to an Azure Log Analytics workspace.

.PARAMETER NextDNSApiKey
    Your NextDNS API key.

.PARAMETER WorkspaceId
    Azure Log Analytics workspace ID.

.PARAMETER WorkspaceKey
    Azure Log Analytics primary or secondary shared key.

.PARAMETER LogType
    Custom log table name in Log Analytics (default: NextDNS_CL).

.PARAMETER LookbackMinutes
    How many minutes of logs to pull (default: 60). Max allowed by NextDNS API is 1440 (24h).

.EXAMPLE
    .\Send-NextDNSLogs.ps1 `
        -NextDNSApiKey "abc123" `
        -WorkspaceId "00000000-0000-0000-0000-000000000000" `
        -WorkspaceKey "base64key==" `
        -LookbackMinutes 60
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$NextDNSApiKey,

    [Parameter(Mandatory)]
    [string]$WorkspaceId,

    [Parameter(Mandatory)]
    [string]$WorkspaceKey,

    [string]$LogType = "NextDNS_CL",

    [ValidateRange(1, 1440)]
    [int]$LookbackMinutes = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/function-app/Modules/NextDNSLogCollector/NextDNSLogCollector.psm1" -Force

Write-Host "Fetching all NextDNS profiles..."
$profiles = @(Get-NextDNSProfiles -ApiKey $NextDNSApiKey)
Write-Host "Retrieved $($profiles.Count) profile(s)."

$allLogs = @()
foreach ($profile in $profiles) {
    Write-Host "Pulling NextDNS logs for profile '$($profile.id)' ($($profile.name)) over the last $LookbackMinutes minutes..."
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

    # Batch into chunks of 500 to stay well within the 30 MB Log Analytics payload limit.
    $batchSize = 500
    for ($i = 0; $i -lt $flatLogs.Count; $i += $batchSize) {
        $batch = $flatLogs[$i..[Math]::Min($i + $batchSize - 1, $flatLogs.Count - 1)]
        Send-ToLogAnalytics -WorkspaceId $WorkspaceId -WorkspaceKey $WorkspaceKey -LogType $LogType -Logs $batch
    }
} else {
    Write-Host "No logs to send."
}
