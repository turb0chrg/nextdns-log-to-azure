#Requires -Version 7.0
<#
.SYNOPSIS
    Pulls logs from the NextDNS API and sends them to an Azure Log Analytics workspace.

.PARAMETER NextDNSApiKey
    Your NextDNS API key.

.PARAMETER NextDNSProfileId
    Your NextDNS profile ID.

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
        -NextDNSProfileId "abc123" `
        -WorkspaceId "00000000-0000-0000-0000-000000000000" `
        -WorkspaceKey "base64key==" `
        -LookbackMinutes 60
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$NextDNSApiKey,

    [Parameter(Mandatory)]
    [string]$NextDNSProfileId,

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

Write-Host "Pulling NextDNS logs for the last $LookbackMinutes minutes..."
$logs = Get-NextDNSLogs -ApiKey $NextDNSApiKey -ProfileId $NextDNSProfileId -LookbackMinutes $LookbackMinutes
Write-Host "Retrieved $($logs.Count) log entries."

$flatLogs = $logs | ForEach-Object { ConvertTo-FlatLogEntry -Entry $_ }

# Batch into chunks of 500 to stay well within the 30 MB Log Analytics payload limit.
$batchSize = 500
for ($i = 0; $i -lt $flatLogs.Count; $i += $batchSize) {
    $batch = $flatLogs[$i..[Math]::Min($i + $batchSize - 1, $flatLogs.Count - 1)]
    Send-ToLogAnalytics -WorkspaceId $WorkspaceId -WorkspaceKey $WorkspaceKey -LogType $LogType -Logs $batch
}
