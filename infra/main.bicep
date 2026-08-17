// =============================================================================
// main.bicep — Top-level orchestrator for the Beer Tracker infrastructure
//
//  Deployment order:
//    1. monitoring-workspace  — Log Analytics workspace (no AKS dep)
//    2. network               — VNet, subnets, Application Gateway
//    3. acr                   — Azure Container Registry
//    4. aks                   — AKS cluster (depends on 1, 2, 3)
//    5. keyvault              — Key Vault, UMIs, federated creds (depends on 4)
//    6. postgres              — Flexible Server + databases (depends on 2)
//    7. monitoring-alerts     — Alert rules (depends on 4; re-applies workspace idempotently)
//
//  Role assignments wired in this file (require both module outputs):
//    • AcrPull     — AKS kubelet identity → ACR
//    • Contributor — AGIC identity → Application Gateway
// =============================================================================

targetScope = 'resourceGroup'

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------

@description('Azure region for all resources. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Short project name prefix used to construct all resource names (lowercase, alphanumeric, max 12 chars).')
@maxLength(12)
param projectName string

@description('Environment name used to differentiate deployments (e.g., dev, staging, prod).')
@allowed([
  'dev'
  'staging'
  'prod'
])
param environment string

@description('Administrator password for the PostgreSQL Flexible Server.')
@secure()
param adminPassword string

@description('RSA-256 private key (PEM format) stored in Key Vault for auth-service JWT signing.')
@secure()
param authRs256PrivateKey string

@description('Password for the auth_db service database user stored in Key Vault.')
@secure()
param authDbPassword string

@description('Password for the tracking_db service database user stored in Key Vault.')
@secure()
param trackingDbPassword string

@description('Password for the notifications_db service database user stored in Key Vault.')
@secure()
param notificationsDbPassword string

@description('Password for the statistics_db service database user stored in Key Vault.')
@secure()
param statisticsDbPassword string

@description('Shared internal API key for service-to-service authentication stored in Key Vault.')
@secure()
param internalApiKey string

@description('Email address for Azure Monitor alert notifications.')
param alertEmailAddress string = 'platform-alerts@example.com'

// ---------------------------------------------------------------------------
// Role definition IDs (built-in)
// ---------------------------------------------------------------------------

var acrPullRoleId    = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
var contributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')

// ---------------------------------------------------------------------------
// Phase 1 — Monitoring: create the Log Analytics workspace first so AKS can
//           reference it without a circular module dependency.
// ---------------------------------------------------------------------------

module monitoringWorkspace 'monitoring.bicep' = {
  name: 'monitoring-workspace'
  params: {
    location: location
    projectName: projectName
    environment: environment
    aksClusterId: ''       // No AKS yet; alert rules created in phase 7
    appGwId: ''
    alertEmailAddress: alertEmailAddress
  }
}

// ---------------------------------------------------------------------------
// Phase 2 — Network: VNet, subnets, and Application Gateway
// ---------------------------------------------------------------------------

module network 'network.bicep' = {
  name: 'network'
  params: {
    location: location
    projectName: projectName
    environment: environment
  }
}

// ---------------------------------------------------------------------------
// Phase 3 — ACR: Container Registry
// ---------------------------------------------------------------------------

module acr 'acr.bicep' = {
  name: 'acr'
  params: {
    location: location
    projectName: projectName
    environment: environment
  }
}

// ---------------------------------------------------------------------------
// Phase 4 — AKS cluster
//   • Depends on monitoring (workspace must exist for Container Insights)
//   • Depends on network (subnet + AppGW IDs)
// ---------------------------------------------------------------------------

module aks 'aks.bicep' = {
  name: 'aks'
  params: {
    location: location
    projectName: projectName
    environment: environment
    aksSubnetId: network.outputs.aksSubnetId
    appGwId: network.outputs.appGwId
    logAnalyticsWorkspaceId: monitoringWorkspace.outputs.workspaceId
  }
}

// ---------------------------------------------------------------------------
// Phase 4a — Cross-module role assignments that require both ACR and AKS
// ---------------------------------------------------------------------------

// AKS kubelet identity → AcrPull on ACR (allows nodes to pull images)
resource existingAcr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acr.outputs.acrName
}

resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.outputs.acrId, aks.outputs.kubeletIdentityObjectId, acrPullRoleId)
  scope: existingAcr
  properties: {
    roleDefinitionId: acrPullRoleId
    principalId: aks.outputs.kubeletIdentityObjectId
    principalType: 'ServicePrincipal'
  }
}

// AGIC managed identity → Contributor on Application Gateway
// (AGIC addon needs to create/update routing rules and backend pools)
resource existingAppGw 'Microsoft.Network/applicationGateways@2024-05-01' existing = {
  name: network.outputs.appGwName
}

resource agicContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(network.outputs.appGwId, aks.outputs.agicIdentityObjectId, contributorRoleId)
  scope: existingAppGw
  properties: {
    roleDefinitionId: contributorRoleId
    principalId: aks.outputs.agicIdentityObjectId
    principalType: 'ServicePrincipal'
  }
}

// ---------------------------------------------------------------------------
// Phase 5 — Key Vault, managed identities, federated credentials, and secrets
//   • Depends on AKS (OIDC issuer URL for federated credentials)
// ---------------------------------------------------------------------------

module keyvault 'keyvault.bicep' = {
  name: 'keyvault'
  params: {
    location: location
    projectName: projectName
    environment: environment
    oidcIssuerUrl: aks.outputs.oidcIssuerUrl
    authRs256PrivateKey: authRs256PrivateKey
    authDbPassword: authDbPassword
    trackingDbPassword: trackingDbPassword
    notificationsDbPassword: notificationsDbPassword
    statisticsDbPassword: statisticsDbPassword
    internalApiKey: internalApiKey
  }
}

// ---------------------------------------------------------------------------
// Phase 6 — PostgreSQL Flexible Server
//   • Depends on network (postgres subnet + VNet IDs)
//   • Runs in parallel with keyvault (no interdependency)
// ---------------------------------------------------------------------------

module postgres 'postgres.bicep' = {
  name: 'postgres'
  params: {
    location: location
    projectName: projectName
    environment: environment
    postgresSubnetId: network.outputs.postgresSubnetId
    vnetId: network.outputs.vnetId
    adminPassword: adminPassword
  }
}

// ---------------------------------------------------------------------------
// Phase 7 — Monitoring: create alert rules now that we have the AKS cluster ID
//   The workspace re-apply is idempotent in ARM incremental mode.
// ---------------------------------------------------------------------------

module monitoringAlerts 'monitoring.bicep' = {
  name: 'monitoring-alerts'
  params: {
    location: location
    projectName: projectName
    environment: environment
    aksClusterId: aks.outputs.clusterId
    appGwId: network.outputs.appGwId
    alertEmailAddress: alertEmailAddress
  }
}

// ---------------------------------------------------------------------------
// Outputs — expose key values for post-deploy configuration (CI/CD, K8s setup)
// ---------------------------------------------------------------------------

@description('Login server of the Azure Container Registry.')
output acrLoginServer string = acr.outputs.loginServer

@description('Name of the AKS cluster.')
output aksClusterName string = aks.outputs.clusterName

@description('OIDC issuer URL for the AKS cluster (used to configure additional federated credentials).')
output oidcIssuerUrl string = aks.outputs.oidcIssuerUrl

@description('Name of the Key Vault.')
output keyVaultName string = keyvault.outputs.keyVaultName

@description('URI of the Key Vault.')
output keyVaultUri string = keyvault.outputs.keyVaultUri

@description('FQDN of the PostgreSQL Flexible Server.')
output postgresFqdn string = postgres.outputs.serverFqdn

@description('Log Analytics workspace ID.')
output logAnalyticsWorkspaceId string = monitoringWorkspace.outputs.workspaceId

@description('Public IP address of the Application Gateway / ingress.')
output ingressPublicIp string = network.outputs.appGwPublicIp

@description('Managed identity client IDs for workload identity annotation on K8s service accounts.')
output serviceIdentityClientIds object = {
  authService: keyvault.outputs.authServiceClientId
  beerTrackingService: keyvault.outputs.beerTrackingServiceClientId
  healthNotificationService: keyvault.outputs.healthNotificationServiceClientId
  statisticsService: keyvault.outputs.statisticsServiceClientId
}
