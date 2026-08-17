// =============================================================================
// network.bicep — Virtual Network, subnets, and Application Gateway
// =============================================================================

@description('Azure region for all resources.')
param location string

@description('Project name prefix used for resource naming.')
param projectName string

@description('Environment name (e.g., dev, staging, prod).')
param environment string

// ---------------------------------------------------------------------------
// Variables
// ---------------------------------------------------------------------------

var vnetName       = '${projectName}-${environment}-vnet'
var appGwName      = '${projectName}-${environment}-appgw'
var appGwPipName   = '${projectName}-${environment}-appgw-pip'

// ---------------------------------------------------------------------------
// Virtual Network with subnets
// ---------------------------------------------------------------------------

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'aks-subnet'
        properties: {
          addressPrefix: '10.0.1.0/24'
          // AKS uses azure CNI — no service-endpoint restrictions needed at this level
        }
      }
      {
        name: 'appgw-subnet'
        properties: {
          addressPrefix: '10.0.2.0/24'
        }
      }
      {
        name: 'postgres-subnet'
        properties: {
          addressPrefix: '10.0.3.0/24'
          delegations: [
            {
              name: 'postgres-delegation'
              properties: {
                serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers'
              }
            }
          ]
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Application Gateway Public IP (Standard SKU required for Standard_v2 AppGW)
// ---------------------------------------------------------------------------

resource appGwPip 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: appGwPipName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: '${projectName}-${environment}-ingress'
    }
  }
}

// ---------------------------------------------------------------------------
// Application Gateway (Standard_v2) — managed by AGIC addon
// AGIC will overwrite backend pools, rules, and listeners at runtime.
// The minimal configuration below satisfies the ARM validation requirement.
// ---------------------------------------------------------------------------

resource appGw 'Microsoft.Network/applicationGateways@2024-05-01' = {
  name: appGwName
  location: location
  properties: {
    sku: {
      name: 'Standard_v2'
      tier: 'Standard_v2'
      capacity: 2
    }
    gatewayIPConfigurations: [
      {
        name: 'appGwIpConfig'
        properties: {
          subnet: {
            id: '${vnet.id}/subnets/appgw-subnet'
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appGwFrontendIp'
        properties: {
          publicIPAddress: {
            id: appGwPip.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port80'
        properties: {
          port: 80
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'defaultBackendPool'
        properties: {}
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'defaultHttpSettings'
        properties: {
          port: 80
          protocol: 'Http'
          cookieBasedAffinity: 'Disabled'
          requestTimeout: 30
          pickHostNameFromBackendAddress: false
        }
      }
    ]
    httpListeners: [
      {
        name: 'defaultHttpListener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appGwName, 'appGwFrontendIp')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGwName, 'port80')
          }
          protocol: 'Http'
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'defaultRoutingRule'
        properties: {
          ruleType: 'Basic'
          priority: 100
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGwName, 'defaultHttpListener')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGwName, 'defaultBackendPool')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGwName, 'defaultHttpSettings')
          }
        }
      }
    ]
    enableHttp2: true
    autoscaleConfiguration: {
      minCapacity: 1
      maxCapacity: 10
    }
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Resource ID of the virtual network.')
output vnetId string = vnet.id

@description('Name of the virtual network.')
output vnetName string = vnet.name

@description('Resource ID of the AKS subnet.')
output aksSubnetId string = '${vnet.id}/subnets/aks-subnet'

@description('Resource ID of the Application Gateway subnet.')
output appgwSubnetId string = '${vnet.id}/subnets/appgw-subnet'

@description('Resource ID of the PostgreSQL subnet.')
output postgresSubnetId string = '${vnet.id}/subnets/postgres-subnet'

@description('Resource ID of the Application Gateway.')
output appGwId string = appGw.id

@description('Name of the Application Gateway.')
output appGwName string = appGw.name

@description('Public IP address of the Application Gateway.')
output appGwPublicIp string = appGwPip.properties.ipAddress
