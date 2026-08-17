// =============================================================================
// aks.bicep — AKS cluster with AGIC, Workload Identity, Secrets Store CSI,
//             and Container Insights
// =============================================================================

@description('Azure region for all resources.')
param location string

@description('Project name prefix used for resource naming.')
param projectName string

@description('Environment name (e.g., dev, staging, prod).')
param environment string

@description('Resource ID of the AKS node subnet (Azure CNI).')
param aksSubnetId string

@description('Resource ID of the existing Application Gateway for AGIC addon.')
param appGwId string

@description('Resource ID of the Log Analytics workspace for Container Insights.')
param logAnalyticsWorkspaceId string

// ---------------------------------------------------------------------------
// Variables
// ---------------------------------------------------------------------------

var clusterName       = '${projectName}-${environment}-aks'
var identityName      = '${projectName}-${environment}-aks-identity'

// Built-in role: Network Contributor
var networkContributorRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '4d97b98b-1d4f-4787-a291-c67834d212e8'
)

// ---------------------------------------------------------------------------
// User-assigned managed identity for the AKS control plane
// ---------------------------------------------------------------------------

resource aksIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
}

// Grant the control-plane identity Network Contributor on the AKS subnet so
// it can manage load-balancer and node NICs.
resource aksSubnetRef 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  // Derive VNet name and subnet name from the provided subnet resource ID
  name: '${split(aksSubnetId, '/')[8]}/${split(aksSubnetId, '/')[10]}'
}

resource aksIdentityNetworkContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aksSubnetId, aksIdentity.id, networkContributorRoleId)
  scope: aksSubnetRef
  properties: {
    roleDefinitionId: networkContributorRoleId
    principalId: aksIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ---------------------------------------------------------------------------
// AKS Cluster
// ---------------------------------------------------------------------------

resource aks 'Microsoft.ContainerService/managedClusters@2024-09-01' = {
  name: clusterName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${aksIdentity.id}': {}
    }
  }
  properties: {
    dnsPrefix: '${projectName}-${environment}'
    kubernetesVersion: '1.30'
    enableRBAC: true
    disableLocalAccounts: true

    // ---- Entra ID managed integration with Azure RBAC --------------------
    // Disables static certificate-based credentials; all API server access is
    // authenticated via Entra ID. Grant cluster access via Azure RBAC role
    // assignments on the AKS resource (e.g. "Azure Kubernetes Service RBAC
    // Cluster Admin") rather than Kubernetes RBAC bindings.
    aadProfile: {
      managed: true
      enableAzureRBAC: true
    }

    // ---- Workload Identity & OIDC ----------------------------------------
    oidcIssuerProfile: {
      enabled: true
    }
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }

    // ---- Node pools -------------------------------------------------------
    agentPoolProfiles: [
      {
        name: 'system'
        mode: 'System'
        count: 2
        minCount: 2
        maxCount: 5
        enableAutoScaling: true
        vmSize: 'Standard_D2s_v3'
        osDiskSizeGB: 128
        osDiskType: 'Managed'
        osType: 'Linux'
        osSKU: 'AzureLinux'
        vnetSubnetID: aksSubnetId
        maxPods: 110
        upgradeSettings: {
          maxSurge: '33%'
        }
        nodeTaints: []
      }
    ]

    // ---- Networking -------------------------------------------------------
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'azure'
      serviceCidr: '10.1.0.0/16'
      dnsServiceIP: '10.1.0.10'
      loadBalancerSku: 'standard'
      outboundType: 'loadBalancer'
    }

    // ---- Add-ons ----------------------------------------------------------
    addonProfiles: {
      // Application Gateway Ingress Controller
      ingressApplicationGateway: {
        enabled: true
        config: {
          applicationGatewayId: appGwId
        }
      }
      // Container Insights (Azure Monitor for containers)
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
          useAADAuth: 'true'
        }
      }
      // Secrets Store CSI Driver (Azure Key Vault provider)
      azureKeyvaultSecretsProvider: {
        enabled: true
        config: {
          enableSecretRotation: 'true'
          rotationPollInterval: '2m'
        }
      }
    }

    // ---- Upgrade ----------------------------------------------------------
    autoUpgradeProfile: {
      upgradeChannel: 'patch'
      nodeOSUpgradeChannel: 'NodeImage'
    }

  }

  dependsOn: [
    aksIdentityNetworkContributor
  ]
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Resource ID of the AKS cluster.')
output clusterId string = aks.id

@description('Name of the AKS cluster.')
output clusterName string = aks.name

@description('OIDC issuer URL for Workload Identity federated credentials.')
output oidcIssuerUrl string = aks.properties.oidcIssuerProfile.issuerURL

@description('Object ID of the AKS kubelet managed identity (used for ACR pull).')
output kubeletIdentityObjectId string = aks.properties.identityProfile.kubeletidentity.objectId

@description('Client ID of the AKS kubelet managed identity.')
output kubeletIdentityClientId string = aks.properties.identityProfile.kubeletidentity.clientId

@description('Object ID of the AGIC managed identity (used to manage the Application Gateway).')
output agicIdentityObjectId string = aks.properties.addonProfiles.ingressApplicationGateway.identity.objectId

@description('Principal ID of the AKS control-plane managed identity.')
output aksIdentityPrincipalId string = aksIdentity.properties.principalId
