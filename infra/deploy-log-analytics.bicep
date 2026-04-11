@description('Name of the Log Analytics Workspace')
param workspaceName string

@description('Location for the Log Analytics Workspace')
param location string = resourceGroup().location

@description('The pricing tier for the Log Analytics Workspace. Default is "PerGB2018".')
param pricingTier string = 'PerGB2018'

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: workspaceName
  location: location
  properties: {
    sku: {
      name: pricingTier
    }
    retentionInDays: 30 // Default retention period
  }
}

output workspaceId string = logAnalyticsWorkspace.id
output workspaceName string = logAnalyticsWorkspace.name