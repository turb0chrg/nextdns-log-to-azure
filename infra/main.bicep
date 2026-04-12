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

@description('Group object ID to assign Key Vault Secrets Officer role')
param keyVaultSecretsOfficerObjectId string

@description('Log Analytics workspace shared key')
@secure()
param logAnalyticsWorkspaceKey string

@description('How many minutes of logs to pull on each run')
param lookbackMinutes int = 60

@description('Timer cron expression (default: every hour)')
param timerSchedule string = '0 0 * * * *'

// Role definition ID for Key Vault Secrets User (built-in)
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'
var keyVaultSecretsOfficerRoleId = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'

module logAnalytics 'deploy-log-analytics.bicep' = {
  name: 'logAnalytics'
  params: {
    workspaceName: workspaceName
    location: location
    pricingTier: pricingTier
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${workspaceName}-appi'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.outputs.workspaceId
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
    applicationInsightsInstrumentationKey: appInsights.properties.InstrumentationKey
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
  name: guid(keyVaultResource.id, functionAppName, keyVaultSecretsUserRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: functionApp.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

resource keyVaultSecretsOfficerAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVaultResource
  name: guid(keyVaultResource.id, keyVaultSecretsOfficerObjectId, keyVaultSecretsOfficerRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsOfficerRoleId)
    principalId: keyVaultSecretsOfficerObjectId
    principalType: 'Group'
  }
}

output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId
output logAnalyticsWorkspaceName string = logAnalytics.outputs.workspaceName
output applicationInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
output applicationInsightsName string = appInsights.name
output keyVaultUri string = keyVault.outputs.keyVaultUri
output functionAppHostName string = functionApp.outputs.functionAppDefaultHostName
