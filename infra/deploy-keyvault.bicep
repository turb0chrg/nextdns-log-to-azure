@description('Name of the Key Vault')
param keyVaultName string

@description('Location for the Key Vault')
param location string = resourceGroup().location

@description('NextDNS API key')
@secure()
param nextDnsApiKey string

@description('Log Analytics workspace shared key')
@secure()
param logAnalyticsWorkspaceKey string

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
  }
}

resource secretNextDnsApiKey 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {
  parent: keyVault
  name: 'nextdns-api-key'
  properties: {
    value: nextDnsApiKey
  }
}

resource secretLogAnalyticsKey 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {
  parent: keyVault
  name: 'log-analytics-workspace-key'
  properties: {
    value: logAnalyticsWorkspaceKey
  }
}

output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
