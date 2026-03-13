@description('Location for the resource.')
param location string = resourceGroup().location

@description('Tags for the resource.')
param tags object = {}

@description('Name of the Container Apps managed environment.')
param containerAppsEnvironmentName string

@description('PostgreSQL database host.')
param databaseHost string

@description('PostgreSQL database port.')
param databasePort string

@description('PostgreSQL database name.')
param databaseName string

@description('PostgreSQL database user.')
param databaseUser string

@description('PostgreSQL database password.')
@secure()
param databasePassword string

@description('Name for the App.')
param name string

@description('Name of the container.')
param containerName string = 'litellm'

@description('Name of the container registry.')
param containerRegistryName string

@description('Port exposed by the LiteLLM container.')
param containerPort int

@description('Minimum replica count for LiteLLM containers.')
param containerMinReplicaCount int

@description('Maximum replica count for LiteLLM containers.')
param containerMaxReplicaCount int

// @description('Name of the Key Vault.')
// param keyvaultName string

@description('Master key for LiteLLM. Your master key for the proxy server.')
@secure()
param litellm_master_key string

@description('Salt key for LiteLLM. (CAN NOT CHANGE ONCE SET)')
@secure()
param litellm_salt_key string

@description('OpenAI API key.')
@secure()
param openai_api_key string

@description('Anthropic API key.')
@secure()
param anthropic_api_key string

@description('Azure AI Foundry API key.')
@secure()
param azure_ai_foundry_api_key string

@description('Azure AI Foundry API base URL.')
param azure_ai_foundry_api_base string

@description('Groq API key.')
@secure()
param groq_api_key string

param litellmContainerAppExists bool

@description('Custom domain name for the app (optional). Leave empty for default Azure domain.')
param customDomainName string = ''

@description('Domain validation method for managed certificate.')
@allowed(['CNAME', 'HTTP'])
param domainValidationMethod string = 'CNAME'

var abbrs = loadJsonContent('../abbreviations.json')
var identityName = '${abbrs.managedIdentityUserAssignedIdentities}${name}'

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: containerRegistryName
}

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2023-04-01-preview' existing = {
  name: containerAppsEnvironmentName
}

// resource keyvault 'Microsoft.KeyVault/vaults@2024-11-01' existing = {
//   name: keyvaultName
// }

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
}

resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: containerRegistry
  name: guid(subscription().id, resourceGroup().id, identity.id, 'acrPullRole')
  properties: {
    roleDefinitionId:  subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // ACR Pull role
    principalType: 'ServicePrincipal'
    principalId: identity.properties.principalId
  }
}

// resource keyvaultAccessPolicy 'Microsoft.KeyVault/vaults/accessPolicies@2023-07-01' = {
//   parent: keyvault
//   name: 'add'
//   properties: {
//     accessPolicies: [
//       {
//         objectId: identity.properties.principalId
//         permissions: { secrets: [ 'get', 'list' ] }
//         tenantId: subscription().tenantId
//       }
//     ]
//   }
// }

module fetchLatestContainerImage '../shared/fetch-container-image.bicep' = {
  name: '${name}-fetch-image'
  params: {
    exists: litellmContainerAppExists
    containerAppName: name
  }
}

// module keyvaultSecretMasterKey '../shared/keyvault-secret.bicep' = {
//   name: '${name}-master-key'
//   params: {
//     keyvaultName: keyvaultName
//     secretName: 'LITELLM_MASTER_KEY'
//     secretValue: litellm_master_key
//   }
// }

// module keyvaultSecretSaltKey '../shared/keyvault-secret.bicep' = {
//   name: '${name}-salt-key'
//   params: {
//     keyvaultName: keyvaultName
//     secretName: 'LITELLM_SALT_KEY'
//     secretValue: litellm_salt_key
//   }
// }

// module keyVaultSecretPostgreSQLConnectionString '../shared/keyvault-secret.bicep' = {
//   name: '${name}-postgresql-connection-string'
//   params: {
//     keyvaultName: keyvaultName
//     secretName: 'DATABASE_URL'
//     secretValue: postgresqlConnectionString
//   }
// }

resource managedCertificate 'Microsoft.App/managedEnvironments/managedCertificates@2024-03-01' = if (!empty(customDomainName)) {
  parent: containerAppsEnvironment
  name: '${containerAppsEnvironment.name}-${replace(customDomainName, '.', '-')}-cert'
  location: location
  tags: tags
  properties: {
    subjectName: customDomainName
    domainControlValidation: domainValidationMethod
  }
}

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: name
  location: location
  tags: union(tags, {'azd-service-name':  'litellm' })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${identity.id}': {} }
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: containerPort
        transport: 'auto'
        customDomains: empty(customDomainName) ? [] : [
          {
            name: customDomainName
            certificateId: !empty(customDomainName) ? managedCertificate.id : null
            bindingType: 'SniEnabled'
          }
        ]
      }
      registries: [
        {
          server: containerRegistry.properties.loginServer
          identity: identity.id
        }
      ]
      secrets: [
        {
          name: 'litellm-master-key'
          value: litellm_master_key
          // identity: identity.id
          // keyVaultUrl: 'https://${keyvault.name}.vault.azure.net/secrets/${keyvaultSecretMasterKey.outputs.secretName}'
        }
        {
          name: 'litellm-salt-key'
          value: litellm_salt_key
          // identity: identity.id
          // keyVaultUrl: 'https://${keyvault.name}.vault.azure.net/secrets/${keyvaultSecretSaltKey.outputs.secretName}'
        }
        {
          name: 'db-host'
          value: databaseHost
        }
        {
          name: 'db-port'
          value: databasePort
        }
        {
          name: 'db-name'
          value: databaseName
        }
        {
          name: 'db-user'
          value: databaseUser
        }
        {
          name: 'db-password'
          value: databasePassword
        }
        {
          name: 'openai-api-key'
          value: openai_api_key
        }
        {
          name: 'anthropic-api-key'
          value: anthropic_api_key
        }
        {
          name: 'azure-ai-foundry-api-key'
          value: azure_ai_foundry_api_key
        }
        {
          name: 'groq-api-key'
          value: groq_api_key
        }
      ]
    }
    template: {
      containers: [
        {
          name: containerName
          image: fetchLatestContainerImage.outputs.?containers[?0].?image ?? 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
          resources: {
            cpu: json('2.0')
            memory: '4.0Gi'
          }
          env: [
            {
              name: 'LITELLM_MASTER_KEY'
              secretRef: 'litellm-master-key'
            }
            {
              name: 'LITELLM_SALT_KEY'
              secretRef: 'litellm-salt-key'
            }
            {
              name: 'DB_HOST'
              secretRef: 'db-host'
            }
            {
              name: 'DB_PORT'
              secretRef: 'db-port'
            }
            {
              name: 'DB_NAME'
              secretRef: 'db-name'
            }
            {
              name: 'DB_USER'
              secretRef: 'db-user'
            }
            {
              name: 'DB_PASSWORD'
              secretRef: 'db-password'
            }
            {
              name: 'OPENAI_API_KEY'
              secretRef: 'openai-api-key'
            }
            {
              name: 'ANTHROPIC_API_KEY'
              secretRef: 'anthropic-api-key'
            }
            {
              name: 'AZURE_AI_FOUNDRY_API_KEY'
              secretRef: 'azure-ai-foundry-api-key'
            }
            {
              name: 'AZURE_AI_FOUNDRY_API_BASE'
              value: azure_ai_foundry_api_base
            }
            {
              name: 'GROQ_API_KEY'
              secretRef: 'groq-api-key'
            }
            {
              name: 'STORE_MODEL_IN_DB'
              value: 'True'
            }
            {
              name: 'LITELLM_PREMIUM_FEATURES'
              value: 'advanced_rate_limiting,managed_files,sso_auth,custom_guardrails,blocked_users,team_management,audit_logging,budget_tracking,prometheus_metrics,custom_callbacks,email_notifications,vector_store_acl,advanced_dashboard'
            }
          ]
        }
      ]
      scale: {
        minReplicas: containerMinReplicaCount
        maxReplicas: containerMaxReplicaCount
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '100'
              }
            }
          }
        ]
      }
    }
  }
}

output containerAppName string = containerApp.name
output containerAppFQDN string = containerApp.properties.configuration.ingress.fqdn
output domainVerificationCode string = containerApp.properties.customDomainVerificationId
output customDomainConfigured bool = !empty(customDomainName)
output customDomainName string = customDomainName

