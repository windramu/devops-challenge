param name string
param location string = resourceGroup().location
param tags object = {}
param serviceName string = 'api'
param allowedOrigins array = []
param appCommandLine string?
param appInsightResourceId string
param appServicePlanId string
@secure()
param appSettings object = {}
param siteConfig object = {}

@description('Required. Type of site to deploy.')
param kind string

@description('Optional. If client affinity is enabled.')
param clientAffinityEnabled bool = true

@description('Optional. Required if app of kind functionapp. Resource ID of the storage account to manage triggers and logging function executions.')
param storageAccountResourceId string?
param actionGroups string
param appInsightName string

module api 'br/public:avm/res/web/site:0.6.0' = {
  name: '${name}-app-module'
  params: {
    kind: kind
    name: name
    serverFarmResourceId: appServicePlanId
    tags: union(tags, { 'azd-service-name': serviceName })
    location: location
    appInsightResourceId: appInsightResourceId
    clientAffinityEnabled: clientAffinityEnabled
    storageAccountResourceId: storageAccountResourceId
    managedIdentities: {
      systemAssigned: true
    }
    siteConfig: union(siteConfig, {
      cors: {
        allowedOrigins: union(['https://portal.azure.com', 'https://ms.portal.azure.com'], allowedOrigins)
      }
      appCommandLine: appCommandLine
    })
    appSettingsKeyValuePairs: union(
      appSettings,
      { ENABLE_ORYX_BUILD: true, ApplicationInsightsAgent_EXTENSION_VERSION: contains(kind, 'linux') ? '~3' : '~2' }
    )
    logsConfiguration: {
      applicationLogs: { fileSystem: { level: 'Verbose' } }
      detailedErrorMessages: { enabled: true }
      failedRequestsTracing: { enabled: true }
      httpLogs: { fileSystem: { enabled: true, retentionInDays: 1, retentionInMb: 35 } }
    }
  }
}

resource apiAlert 'microsoft.insights/metricAlerts@2018-03-01' = {
  name: '${name}-request-alert'
  location: 'global'
  properties: {
    severity: 3
    enabled: true
    scopes: [
      api.outputs.resourceId
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      allOf: [
        {
          threshold: json('10')
          name: 'Metric1'
          metricNamespace: 'microsoft.web/sites'
          metricName: 'Requests'
          operator: 'GreaterThan'
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    }
    autoMitigate: true
    targetResourceType: 'Microsoft.Web/sites'
    targetResourceRegion: location
    actions: []
  }
}

resource actionRules 'Microsoft.AlertsManagement/actionRules@2021-08-08' = {
  name: '${name}-request-alert-fired'
  location: 'Global'
  properties: {
    scopes: [
      api.outputs.resourceId
    ]
    conditions: [
      {
        field: 'MonitorCondition'
        operator: 'Equals'
        values: [
          'Fired'
        ]
      }
      {
        field: 'AlertRuleName'
        operator: 'Equals'
        values: [
          '${name}-request-alert'
          'Failure Anomalies - ${appInsightName}'
        ]
      }
    ]
    enabled: true
    actions: [
      {
        actionGroupIds: [
          actionGroups
        ]
        actionType: 'AddActionGroups'
      }
    ]
  }
}


output SERVICE_API_IDENTITY_PRINCIPAL_ID string = api.outputs.systemAssignedMIPrincipalId
output SERVICE_API_NAME string = api.outputs.name
output SERVICE_API_URI string = 'https://${api.outputs.defaultHostname}'
