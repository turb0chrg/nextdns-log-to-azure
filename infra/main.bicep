@description('Name of the Function App')
param functionAppName string

@description('Name of the App Service Plan')
param appServicePlanName string

@description('Storage account name for the Function App')
param storageAccountName string

@description('Name of the Log Analytics Workspace')
param workspaceName string

@description('Name of the Key Vault')
param keyVaultName string

@description('Location for all resources')
param location string = resourceGroup().location

@description('The pricing tier for the Log Analytics Workspace')
param pricingTier string = 'PerGB2018'

@description('NextDNS API key')
@secure()
param nextDnsApiKey string

@description('NextDNS profile ID')
param nextDnsProfileId string

@description('Log Analytics workspace shared key')
@secure()
param logAnalyticsWorkspaceKey string

@description('How many minutes of logs to pull on each run')
param lookbackMinutes int = 60

@description('Timer cron expression (default: every hour)')
param timerSchedule string = '0 0 * * * *'

// Role definition ID for Key Vault Secrets User (built-in)
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

module logAnalytics 'deploy-log-analytics.bicep' = {
  name: 'logAnalytics'
  params: {
    workspaceName: workspaceName
    location: location
    pricingTier: pricingTier
  }
}

module keyVault 'deploy-keyvault.bicep' = {
  name: 'keyVault'
  params: {
    keyVaultName: keyVaultName
    location: location
    nextDnsApiKey: nextDnsApiKey
    logAnalyticsWorkspaceKey: logAnalyticsWorkspaceKey
  }
}

module functionApp 'deploy-function-app.bicep' = {
  name: 'functionApp'
  params: {
    functionAppName: functionAppName
    location: location
    appServicePlanName: appServicePlanName
    storageAccountName: storageAccountName
    nextDnsProfileId: nextDnsProfileId
    keyVaultName: keyVault.outputs.keyVaultName
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    lookbackMinutes: lookbackMinutes
    timerSchedule: timerSchedule
  }
}

// Grant the Function App's managed identity read access to Key Vault secrets
resource keyVaultResource 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: keyVaultName
}

resource keyVaultSecretsUserAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVaultResource
  name: guid(keyVaultResource.id, functionApp.outputs.principalId, keyVaultSecretsUserRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: functionApp.outputs.principalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [keyVault, functionApp]
}

output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId
output logAnalyticsWorkspaceName string = logAnalytics.outputs.workspaceName
output keyVaultUri string = keyVault.outputs.keyVaultUri
output functionAppHostName string = functionApp.outputs.functionAppDefaultHostName
