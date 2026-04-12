@description('Name of the Function App')
param functionAppName string

@description('Location for the Function App')
param location string = resourceGroup().location

@description('Name of the App Service Plan')
param appServicePlanName string

@description('Storage account name for the Function App')
param storageAccountName string

@description('NextDNS profile ID')
param nextDnsProfileId string

@description('Name of the Key Vault holding secrets')
param keyVaultName string

@description('Log Analytics workspace ID')
param logAnalyticsWorkspaceId string

@description('Application Insights instrumentation key')
param applicationInsightsInstrumentationKey string

@description('How many minutes of logs to pull on each run')
param lookbackMinutes int = 60

@description('Timer cron expression (default: every hour)')
param timerSchedule string = '0 0 * * * *'

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
}

resource appServicePlan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: true
  }
}

resource functionApp 'Microsoft.Web/sites@2022-03-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'powershell'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'NEXTDNS_API_KEY'
          value: '@Microsoft.KeyVault(VaultName=${keyVaultName};SecretName=nextdns-api-key)'
        }
        {
          name: 'NEXTDNS_PROFILE_ID'
          value: nextDnsProfileId
        }
        {
          name: 'LOG_ANALYTICS_WORKSPACE_ID'
          value: logAnalyticsWorkspaceId
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: 'InstrumentationKey=${applicationInsightsInstrumentationKey}'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsightsInstrumentationKey
        }
        {
          name: 'LOG_ANALYTICS_WORKSPACE_KEY'
          value: '@Microsoft.KeyVault(VaultName=${keyVaultName};SecretName=log-analytics-workspace-key)'
        }
        {
          name: 'LOOKBACK_MINUTES'
          value: string(lookbackMinutes)
        }
        {
          name: 'TIMER_SCHEDULE'
          value: timerSchedule
        }
      ]
      powerShellVersion: '7.2'
    }
  }
}

output functionAppId string = functionApp.id
output functionAppDefaultHostName string = functionApp.properties.defaultHostName
output principalId string = functionApp.identity.principalId
