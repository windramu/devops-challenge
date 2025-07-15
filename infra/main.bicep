targetScope = 'resourceGroup' //resourceGroup or subscription

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

// Optional parameters to override the default azd resource naming conventions. Update the main.parameters.json file to provide values. e.g.,:
// "resourceGroupName": {
//      "value": "myGroupName"
// }
param apiServiceName string = ''
param applicationInsightsDashboardName string = ''
param applicationInsightsName string = ''
param appServicePlanName string = ''
param cosmosAccountName string = ''
param keyVaultName string = ''
param logAnalyticsName string = ''
param resourceGroupName string
param webServiceName string = ''
#disable-next-line no-unused-params
param guidValue string = newGuid()

#disable-next-line no-unused-params
param dateInfo string = utcNow('ddMM')


@description('Id of the user or app to assign application roles')
param principalId string = ''

//var rg = resourceGroupName
var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower('${uniqueString(toLower(uniqueString(resourceGroup().id, environmentName)))}${dateInfo}')
//var resourceToken = toLower(uniqueString(guidValue))
var tags = { 'azd-env-name': environmentName }


// Organize resources in a resource group
// resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
//   name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
//   location: location
//   tags: tags
// }

// The application frontend
module web './app/web-appservice-avm.bicep' = {
  name: 'web'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: !empty(webServiceName) ? webServiceName : '${abbrs.webSitesAppService}web-${resourceToken}'
    location: location
    tags: tags
    appServicePlanId: appServicePlan.outputs.resourceId
    appInsightResourceId: applicationInsights.outputs.applicationInsightsResourceId
    logAnalyticsResourceId: logAnalytics.outputs.resourceId
    linuxFxVersion: 'node|20-lts'
  }
}

// The application backend
module api './app/api-appservice-avm.bicep' = {
  name: 'api'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: !empty(apiServiceName) ? apiServiceName : '${abbrs.webSitesAppService}api-${resourceToken}'
    location: location
    tags: tags
    kind: 'app'
    appServicePlanId: appServicePlan.outputs.resourceId
    siteConfig: {
      // alwaysOn: true
      linuxFxVersion: 'node|20-lts'
    }
    appSettings: {
      AZURE_KEY_VAULT_ENDPOINT: keyVault.outputs.uri
      AZURE_COSMOS_CONNECTION_STRING_KEY: cosmos.outputs.connectionStringKey
      AZURE_COSMOS_DATABASE_NAME: cosmos.outputs.databaseName
      AZURE_COSMOS_ENDPOINT: 'https://${cosmos.outputs.databaseName}.documents.azure.com:443/'
      API_ALLOW_ORIGINS: web.outputs.SERVICE_WEB_URI
      SCM_DO_BUILD_DURING_DEPLOYMENT: true
    }
    appInsightResourceId: applicationInsights.outputs.applicationInsightsResourceId
    appInsightName: applicationInsights.outputs.applicationInsightsName
    allowedOrigins: [ web.outputs.SERVICE_WEB_URI ]
    actionGroups: actionGroups.id
  }
}

// Create a keyvault to store secrets
module keyVault 'br/public:avm/res/key-vault/vault:0.3.5' = {
  name: 'keyvault'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: !empty(keyVaultName) ? keyVaultName : '${abbrs.keyVaultVaults}${resourceToken}'
    location: location
    tags: tags
    // Add keyvault secret
    // secrets: [
    //   {
    //     name: 'database-password'
    //     value: vmAdminPass
    //   }
    // ]
    enableRbacAuthorization: false
    enableVaultForDeployment: true
    enableVaultForTemplateDeployment: true
    enablePurgeProtection: false
    sku: 'standard'
  }
}

// Give the API access to KeyVault
module accessKeyVault 'br/public:avm/res/key-vault/vault:0.3.5' = {
  name: 'accesskeyvault'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: keyVault.outputs.name
    enableRbacAuthorization: false
    enableVaultForDeployment: false
    enableVaultForTemplateDeployment: false
    enablePurgeProtection: false
    sku: 'standard'
    accessPolicies: [
      {
        objectId: principalId
        permissions: {
          secrets: [ 'get', 'list' ]
        }
      }
      {
        objectId: api.outputs.SERVICE_API_IDENTITY_PRINCIPAL_ID
        permissions: {
          secrets: [ 'get', 'list' ]
        }
      }
    ]
  }
}
// Generate random keyvault secrets
// module keyvaultSecretsGenerator './keyvault-secret-generator.bicep' = {
//   name: 'secretsGeneration'
//   params: {
//     keyVaultName: keyVaultName
//     secretNames: [
//       'databasePassword'
//     ]
//     location: location
//   }
// }

resource actionGroups 'microsoft.insights/actionGroups@2024-10-01-preview' = {
  name: 'action-email-notification'
  location: 'Global'
  properties: {
    groupShortName: 'action-email'
    enabled: true
    emailReceivers: [
      {
        name: 'notify-windra'
        emailAddress: 'windra.muballighi@gmail.com'
        useCommonAlertSchema: false
      }
    ]
    smsReceivers: []
    webhookReceivers: []
    eventHubReceivers: []
    itsmReceivers: []
    azureAppPushReceivers: []
    automationRunbookReceivers: []
    voiceReceivers: []
    logicAppReceivers: []
    azureFunctionReceivers: []
    armRoleReceivers: []
  }
}

// The application database
module cosmos './app/db-avm.bicep' = {
  name: 'cosmos'
  scope: resourceGroup(resourceGroupName)
  params: {
    accountName: !empty(cosmosAccountName) ? cosmosAccountName : '${abbrs.documentDBDatabaseAccounts}${resourceToken}'
    location: location
    tags: tags
    keyVaultResourceId: keyVault.outputs.resourceId
  }
}

// Create an App Service Plan to group applications under the same payment plan and SKU
module appServicePlan 'br/public:avm/res/web/serverfarm:0.1.0' = {
  name: 'appserviceplan'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: !empty(appServicePlanName) ? appServicePlanName : '${abbrs.webServerFarms}${resourceToken}'
    sku: {
      name: 'F1'
      tier: 'Free'
    }
    location: location
    tags: tags
    reserved: true
    kind: 'Linux'
    diagnosticSettings: []
  }
}

// Monitor application with Azure Monitor
// module monitoring 'br/public:avm/ptn/azd/monitoring:0.1.0' = {
//   name: 'monitoring'
//   scope: resourceGroup(resourceGroupName)
//   params: {
//     applicationInsightsName: !empty(applicationInsightsName) ? applicationInsightsName : '${abbrs.insightsComponents}${resourceToken}'
//     logAnalyticsName: !empty(logAnalyticsName) ? logAnalyticsName : '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
//     applicationInsightsDashboardName: !empty(applicationInsightsDashboardName) ? applicationInsightsDashboardName : '${abbrs.portalDashboards}${resourceToken}'
//     location: location
//     tags: tags
//   }
// }

// Workspaces
module logAnalytics 'br/public:avm/res/operational-insights/workspace:0.12.0' = {
  name: 'loganalytics'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: !empty(logAnalyticsName) ? logAnalyticsName : '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    location: location
    // dataRetention: 7
    enableTelemetry: true
    // skuName: 'Free'
    dailyQuotaGb: 5
  }
}


// Application Insight
module applicationInsights 'br/public:avm/ptn/azd/insights-dashboard:0.1.2' = {
  name: 'applicationinsights'
  scope: resourceGroup(resourceGroupName)
  params: {
    logAnalyticsWorkspaceResourceId: logAnalytics.outputs.resourceId
    name: !empty(applicationInsightsName) ? applicationInsightsName : '${abbrs.insightsComponents}${resourceToken}'
    location: location
    tags: tags
    dashboardName: !empty(applicationInsightsDashboardName) ? applicationInsightsDashboardName : '${abbrs.portalDashboards}${resourceToken}'
    enableTelemetry: true
  }
}


// Data outputs
output AZURE_COSMOS_CONNECTION_STRING_KEY string = cosmos.outputs.connectionStringKey
output AZURE_COSMOS_DATABASE_NAME string = cosmos.outputs.databaseName

// App outputs
output APPLICATIONINSIGHTS_CONNECTION_STRING string = applicationInsights.outputs.applicationInsightsConnectionString
output AZURE_KEY_VAULT_ENDPOINT string = keyVault.outputs.uri
output AZURE_KEY_VAULT_NAME string = keyVault.outputs.name
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output API_BASE_URL string =  api.outputs.SERVICE_API_URI
output REACT_APP_WEB_BASE_URL string = web.outputs.SERVICE_WEB_URI
output SERVICE_API_ENDPOINTS array = [ api.outputs.SERVICE_API_URI ]
