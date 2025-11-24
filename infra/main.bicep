targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('The Azure region for all resources.')
param location string

@description('Name of the resource group to create or use')
param resourceGroupName string 

@description('Port exposed by the LiteLLM container.')
param containerPort int = 80

@description('Minimum replica count for LiteLLM containers.')
param containerMinReplicaCount int = 2

@description('Maximum replica count for LiteLLM containers.')
param containerMaxReplicaCount int = 3

@description('Host/FQDN of the existing PostgreSQL server.')
param databaseHost string

@description('Port of the existing PostgreSQL server.')
param databasePort string = '5432'

@description('Name of the PostgreSQL database.')
param databaseName string = 'litellmdb'

@description('Username for the PostgreSQL database.')
param databaseUser string

@description('Password for the PostgreSQL database user.')
@secure()
param databasePassword string

param litellmContainerAppExists bool

@description('Master key for LiteLLM. Your master key for the proxy server.')
@secure()
param litellm_master_key string

@description('Salt key for LiteLLM. (CAN NOT CHANGE ONCE SET)')
@secure()
param litellm_salt_key string

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, resourceGroupName, environmentName, location))
var tags = {
  'azd-env-name': environmentName
  'azd-template': 'https://github.com/Build5Nines/azd-litellm'
}

var containerAppName = '${abbrs.appContainerApps}litellm-${resourceToken}'

// Organize resources in a resource group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

module monitoring './shared/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    location: location
    tags: tags
    logAnalyticsName: '${abbrs.operationalInsightsWorkspaces}litellm-${resourceToken}'
    applicationInsightsName: '${abbrs.insightsComponents}litellm-${resourceToken}'
  }
  scope: rg
}

module containerRegistry './shared/container-registry.bicep' = {
  name: 'cotainer-registry'
  params: {
    location: location
    tags: tags
    name: '${abbrs.containerRegistryRegistries}${resourceToken}'
  }
  scope: rg
}

module appsEnv './shared/apps-env.bicep' = {
  name: 'apps-env'
  params: {
    name: '${abbrs.appManagedEnvironments}litellm-${resourceToken}'
    location: location
    tags: tags 
    applicationInsightsName: monitoring.outputs.applicationInsightsName
    logAnalyticsWorkspaceName: monitoring.outputs.logAnalyticsWorkspaceName
  }
  scope: rg
}

// Using existing PostgreSQL database - no provisioning needed

// module keyvault './shared/keyvault.bicep' = {
//   name: 'keyvault'
//   params: {
//     name: '${abbrs.keyVaultVaults}litellm-${resourceToken}'
//     location: location
//     tags: tags
//   }
//   scope: rg
// }

// Deploy LiteLLM Container App via module call.
module litellm './app/litellm.bicep' = {
  name: 'litellm'
  params: {
    name: containerAppName
    containerAppsEnvironmentName: appsEnv.outputs.name
    // keyvaultName: keyvault.outputs.name
    databaseHost: databaseHost
    databasePort: databasePort
    databaseName: databaseName
    databaseUser: databaseUser
    databasePassword: databasePassword
    litellm_master_key: litellm_master_key
    litellm_salt_key: litellm_salt_key

    litellmContainerAppExists: litellmContainerAppExists

    containerRegistryName: containerRegistry.outputs.name
    containerPort: containerPort
    containerMinReplicaCount: containerMinReplicaCount
    containerMaxReplicaCount: containerMaxReplicaCount
  }
  scope: rg
}


output AZURE_CONTAINER_REGISTRY_ENDPOINT string = containerRegistry.outputs.loginServer
output LITELLM_MASTER_KEY string = litellm_master_key
output LITELLM_SALT_KEY string = litellm_salt_key

//output LITELLM_CONTAINER_APP_EXISTS bool = true
// output LITELLM_CONTAINERAPP_FQDN string = litellm.outputs.containerAppFQDN
// output POSTGRESQL_FQDN string = postgresql.outputs.fqdn


