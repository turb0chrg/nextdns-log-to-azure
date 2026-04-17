function Get-NextDNSProfiles {
    param ([string]$ApiKey)

    # Fetch all NextDNS profiles. The /profiles endpoint returns all profiles without pagination.
    $uri     = "https://api.nextdns.io/profiles"
    $headers = @{ "X-Api-Key" = $ApiKey; "Accept" = "application/json" }

    Write-Host "GET $uri"
    $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get

    if ($response.data) {
        return $response.data
    }

    return @()
}

function Get-NextDNSLogs {
    param ([string]$ApiKey, [string]$ProfileId, [int]$LookbackMinutes)

    # Build the initial request URL using a UTC timestamp as the lower bound.
    # The NextDNS API returns up to 1000 entries per page; subsequent pages are
    # fetched via the cursor returned in meta.pagination.
    $from    = (Get-Date).ToUniversalTime().AddMinutes(-$LookbackMinutes).ToString("yyyy-MM-ddTHH:mm:ssZ")
    $uri     = "https://api.nextdns.io/profiles/$ProfileId/logs?from=$from&limit=1000"
    $headers = @{ "X-Api-Key" = $ApiKey; "Accept" = "application/json" }
    $allLogs = [System.Collections.Generic.List[object]]::new()

    do {
        Write-Host "GET $uri"
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
        if ($response.data) { $allLogs.AddRange([object[]]$response.data) }

        # If the API returns a cursor there are more pages; loop until it is absent.
        $cursor = $response.meta.pagination.cursor
        if ($cursor) { $uri = "https://api.nextdns.io/profiles/$ProfileId/logs?cursor=$cursor&limit=1000" }
    } while ($cursor)

    return $allLogs
}

function ConvertTo-FlatLogEntry {
    param ([object]$Entry, [string]$ProfileId, [string]$ProfileName)

    # Log Analytics expands top-level primitives into typed columns (_s, _b, _d, _t).
    # Nested objects and arrays are serialized as a single string column instead.
    # This function promotes device sub-fields to the top level so they get their
    # own queryable columns, and serializes the reasons array to a JSON string.
    $flat = [ordered]@{
        profile_id   = $ProfileId
        profile_name = $ProfileName
        timestamp    = $Entry.timestamp
        domain       = $Entry.domain
        root         = $Entry.root
        tracker      = $Entry.tracker
        encrypted    = $Entry.encrypted
        protocol     = $Entry.protocol
        clientIp     = $Entry.clientIp
        client       = $Entry.client
        status       = $Entry.status
        device_id    = $Entry.device.id
        device_name  = $Entry.device.name
        device_model = $Entry.device.model
        # reasons is an array of {id, name} objects; cardinality varies per entry
        # so it is kept as a JSON string and parsed in KQL with parse_json() when needed.
        reasons      = ($Entry.reasons | ConvertTo-Json -Compress)
    }

    return [pscustomobject]$flat
}

function Send-ToLogAnalytics {
    param ([string]$WorkspaceId, [string]$WorkspaceKey, [string]$LogType, [object[]]$Logs)

    if (-not $Logs -or $Logs.Count -eq 0) { Write-Host "No logs to send."; return }

    if (-not $WorkspaceId) {
        throw "Invalid Log Analytics workspace ID: value is missing. Use the workspace customer ID (GUID)."
    }

    if ($WorkspaceId -match '^/' -or $WorkspaceId -match 'ods\.opinsights\.azure\.com') {
        throw "Invalid Log Analytics workspace ID: received a resource path or hostname. Use the workspace customer ID (GUID), not the workspace resource ID or endpoint."
    }

    $body          = $Logs | ConvertTo-Json -Depth 10 -Compress
    $bodyBytes     = [System.Text.Encoding]::UTF8.GetBytes($body)
    $rfc1123Date   = [System.DateTime]::UtcNow.ToString("r")
    $contentType   = "application/json"
    $resource      = "/api/logs"

    $signature = _Build-Signature `
        -WorkspaceId   $WorkspaceId  -WorkspaceKey  $WorkspaceKey `
        -Date          $rfc1123Date  -ContentLength $bodyBytes.Length `
        -Method        "POST"        -ContentType   $contentType `
        -Resource      $resource

    # time-generated-field tells Log Analytics which field to use as the record
    # timestamp rather than defaulting to ingestion time.
    $response = Invoke-WebRequest `
        -Uri         "https://$WorkspaceId.ods.opinsights.azure.com$resource`?api-version=2016-04-01" `
        -Method      Post `
        -Headers     @{ Authorization = $signature; "Log-Type" = $LogType; "x-ms-date" = $rfc1123Date; "time-generated-field" = "timestamp" } `
        -ContentType $contentType `
        -Body        $bodyBytes

    if ($response.StatusCode -eq 200) {
        Write-Host "Sent $($Logs.Count) entries to Log Analytics ($LogType)."
    } else {
        throw "Log Analytics POST failed: $($response.StatusCode)"
    }
}

# Internal helper — not exported.
function _Build-Signature {
    param ([string]$WorkspaceId, [string]$WorkspaceKey, [string]$Date,
           [int]$ContentLength, [string]$Method, [string]$ContentType, [string]$Resource)

    # The Log Analytics HTTP Data Collector API requires a SharedKey signature.
    # The string-to-hash format is defined at:
    # https://learn.microsoft.com/azure/azure-monitor/logs/data-collector-api
    $stringToHash = "$Method`n$ContentLength`n$ContentType`nx-ms-date:$Date`n$Resource"
    $bytesToHash  = [System.Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes     = [System.Convert]::FromBase64String($WorkspaceKey)
    $hmac         = [System.Security.Cryptography.HMACSHA256]::new($keyBytes)
    $encoded      = [System.Convert]::ToBase64String($hmac.ComputeHash($bytesToHash))
    return "SharedKey ${WorkspaceId}:${encoded}"
}

Export-ModuleMember -Function Get-NextDNSProfiles, Get-NextDNSLogs, ConvertTo-FlatLogEntry, Send-ToLogAnalytics
