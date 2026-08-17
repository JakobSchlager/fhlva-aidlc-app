// =============================================================================
// acr.bicep — Azure Container Registry
// =============================================================================

@description('Azure region for all resources.')
param location string

@description('Project name prefix used for resource naming.')
param projectName string

@description('Environment name (e.g., dev, staging, prod).')
param environment string

// ---------------------------------------------------------------------------
// Variables — ACR name must be globally unique and alphanumeric only
// ---------------------------------------------------------------------------

var acrName = toLower(replace('${projectName}${environment}acr', '-', ''))

// ---------------------------------------------------------------------------
// Container Registry (Standard SKU supports geo-replication and webhooks)
// ---------------------------------------------------------------------------

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    adminUserEnabled: false          // Disable admin user; use RBAC for access
    publicNetworkAccess: 'Enabled'   // AKS pulls images over public endpoint
    zoneRedundancy: 'Disabled'
    anonymousPullEnabled: false
    policies: {
      retentionPolicy: {
        status: 'enabled'
        days: 30
      }
      softDeletePolicy: {
        status: 'enabled'
        retentionDays: 7
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Login server FQDN of the container registry.')
output loginServer string = acr.properties.loginServer

@description('Resource ID of the container registry.')
output acrId string = acr.id

@description('Name of the container registry.')
output acrName string = acr.name
