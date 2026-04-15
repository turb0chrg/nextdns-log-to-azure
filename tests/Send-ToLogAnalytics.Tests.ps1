Import-Module "$PSScriptRoot/../function-app/Modules/NextDNSLogCollector/NextDNSLogCollector.psm1" -Force

Describe 'Send-ToLogAnalytics' {
    Context 'when logs are provided' {
        It 'calls the Log Analytics data collector endpoint once' {
            $workspaceId = '00000000-0000-0000-0000-000000000000'
            $workspaceKey = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('dummykey'))
            $logType = 'NextDNS_CL'
            $logs = @([pscustomobject]@{ timestamp = '2026-01-01T00:00:00Z'; domain = 'example.com'; root = 'example.com' })

            Mock Invoke-WebRequest {
                [pscustomobject]@{ StatusCode = 200 }
            }

            Send-ToLogAnalytics -WorkspaceId $workspaceId -WorkspaceKey $workspaceKey -LogType $logType -Logs $logs

            Assert-MockCalled Invoke-WebRequest -Exactly 1 -Scope It
            Assert-MockCalled Invoke-WebRequest -ParameterFilter {
                $Uri -eq "https://$workspaceId.ods.opinsights.azure.com/api/logs?api-version=2016-04-01"
            } -Scope It
        }

        It 'throws when the Log Analytics endpoint returns a non-200 status code' {
            $workspaceId = '00000000-0000-0000-0000-000000000000'
            $workspaceKey = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('dummykey'))
            $logType = 'NextDNS_CL'
            $logs = @([pscustomobject]@{ timestamp = '2026-01-01T00:00:00Z'; domain = 'example.com'; root = 'example.com' })

            Mock Invoke-WebRequest {
                [pscustomobject]@{ StatusCode = 400 }
            }

            { Send-ToLogAnalytics -WorkspaceId $workspaceId -WorkspaceKey $workspaceKey -LogType $logType -Logs $logs } | Should -Throw
            Assert-MockCalled Invoke-WebRequest -Exactly 1 -Scope It
        }
    }

    Context 'when no logs are provided' {
        It 'does not call Invoke-WebRequest' {
            $workspaceId = '00000000-0000-0000-0000-000000000000'
            $workspaceKey = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('dummykey'))
            $logType = 'NextDNS_CL'
            $logs = @()

            Mock Invoke-WebRequest {
                [pscustomobject]@{ StatusCode = 200 }
            }

            Send-ToLogAnalytics -WorkspaceId $workspaceId -WorkspaceKey $workspaceKey -LogType $logType -Logs $logs

            Assert-MockCalled Invoke-WebRequest -Exactly 0 -Scope It
        }
    }
}
