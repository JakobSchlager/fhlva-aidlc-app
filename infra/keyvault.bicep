// =============================================================================
// keyvault.bicep — Azure Key Vault with RBAC authorization
//
//  Creates:
//    • One Key Vault (standard SKU, RBAC-mode)
//    • Four User-Assigned Managed Identities (one per Java service)
//    • Key Vault Secrets User role assignment for each identity
//    • Federated identity credentials for each identity (AKS Workload Identity)
//    • All six application secrets
// =============================================================================

@description('Azure region for all resources.')
param location string

@description('Project name prefix used for resource naming.')
param projectName string

@description('Environment name (e.g., dev, staging, prod).')
param environment string

@description('OIDC issuer URL from the AKS cluster (required for federated credentials).')
param oidcIssuerUrl string

@description('Kubernetes namespace where the service accounts reside.')
param k8sNamespace string = 'beer-tracker'

// ---- Secrets injected at deploy time ------------------------------------
// These should be supplied via a parameter file backed by Azure Key Vault
// references or passed through a secure CI/CD pipeline variable.

@description('RSA-256 private key used by auth-service for JWT signing (PEM format).')
@secure()
param authRs256PrivateKey string

@description('Password for the auth_db PostgreSQL database.')
@secure()
param authDbPassword string

@description('Password for the tracking_db PostgreSQL database.')
@secure()
param trackingDbPassword string

@description('Password for the notifications_db PostgreSQL database.')
@secure()
param notificationsDbPassword string

@description('Password for the statistics_db PostgreSQL database.')
@secure()
param statisticsDbPassword string

@description('Shared internal API key for service-to-service authentication.')
@secure()
param internalApiKey string

// ---------------------------------------------------------------------------
// Variables
// ---------------------------------------------------------------------------

var kvName = '${projectName}-${environment}-kv'

// Built-in role: Key Vault Secrets User
var kvSecretsUserRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '4633458b-17de-408a-b874-0445c86b69e6'
)

// Service definitions — drives identity, federated credential, and secret lookups
var services = [
  { name: 'auth-service',                saName: 'auth-service' }
  { name: 'beer-tracking-service',       saName: 'beer-tracking-service' }
  { name: 'health-notification-service', saName: 'health-notification-service' }
  { name: 'statistics-service',          saName: 'statistics-service' }
]

// ---------------------------------------------------------------------------
// Key Vault
// ---------------------------------------------------------------------------

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: kvName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true          // Access governed by RBAC, not access policies
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    publicNetworkAccess: 'Enabled'         // AKS pods reach KV via managed identity
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// ---------------------------------------------------------------------------
// User-Assigned Managed Identities — one per Java service
// ---------------------------------------------------------------------------

resource serviceIdentities 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = [
  for svc in services: {
    name: '${projectName}-${environment}-${svc.name}-identity'
    location: location
  }
]

// ---------------------------------------------------------------------------
// Key Vault Secrets User role — grant each identity read access to secrets
// ---------------------------------------------------------------------------

resource kvSecretsUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for (svc, i) in services: {
    name: guid(kv.id, serviceIdentities[i].id, kvSecretsUserRoleId)
    scope: kv
    properties: {
      roleDefinitionId: kvSecretsUserRoleId
      principalId: serviceIdentities[i].properties.principalId
      principalType: 'ServicePrincipal'
    }
  }
]

// ---------------------------------------------------------------------------
// Federated Identity Credentials — bind each UAMI to a Kubernetes service
// account via the AKS OIDC issuer (Workload Identity)
// ---------------------------------------------------------------------------

resource federatedCredentials 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = [
  for (svc, i) in services: {
    parent: serviceIdentities[i]
    name: 'aks-${svc.saName}-fedcred'
    properties: {
      issuer: oidcIssuerUrl
      subject: 'system:serviceaccount:${k8sNamespace}:${svc.saName}'
      audiences: [
        'api://AzureADTokenExchange'
      ]
    }
  }
]

// ---------------------------------------------------------------------------
// Secrets
// ---------------------------------------------------------------------------

resource secretAuthRs256PrivateKey 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'auth-rs256-private-key'
  properties: {
    value: authRs256PrivateKey
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

resource secretAuthDbPassword 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'auth-db-password'
  properties: {
    value: authDbPassword
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

resource secretTrackingDbPassword 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'tracking-db-password'
  properties: {
    value: trackingDbPassword
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

resource secretNotificationsDbPassword 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'notifications-db-password'
  properties: {
    value: notificationsDbPassword
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

resource secretStatisticsDbPassword 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'statistics-db-password'
  properties: {
    value: statisticsDbPassword
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

resource secretInternalApiKey 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'internal-api-key'
  properties: {
    value: internalApiKey
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Name of the Key Vault.')
output keyVaultName string = kv.name

@description('URI of the Key Vault.')
output keyVaultUri string = kv.properties.vaultUri

@description('Resource ID of the Key Vault.')
output keyVaultId string = kv.id

@description('Client ID of the auth-service managed identity.')
output authServiceClientId string = serviceIdentities[0].properties.clientId

@description('Client ID of the beer-tracking-service managed identity.')
output beerTrackingServiceClientId string = serviceIdentities[1].properties.clientId

@description('Client ID of the health-notification-service managed identity.')
output healthNotificationServiceClientId string = serviceIdentities[2].properties.clientId

@description('Client ID of the statistics-service managed identity.')
output statisticsServiceClientId string = serviceIdentities[3].properties.clientId

@description('Array of managed identity client IDs indexed by service order.')
output serviceIdentityClientIds array = [
  for i in range(0, length(services)): serviceIdentities[i].properties.clientId
]
