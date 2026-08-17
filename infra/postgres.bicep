// =============================================================================
// postgres.bicep — Azure Database for PostgreSQL Flexible Server
//                  with private VNet integration and all four service databases
// =============================================================================

@description('Azure region for all resources.')
param location string

@description('Project name prefix used for resource naming.')
param projectName string

@description('Environment name (e.g., dev, staging, prod).')
param environment string

@description('Resource ID of the delegated PostgreSQL subnet.')
param postgresSubnetId string

@description('Resource ID of the virtual network (needed to link the private DNS zone).')
param vnetId string

@description('Administrator login password for the PostgreSQL server.')
@secure()
param adminPassword string

// ---------------------------------------------------------------------------
// Variables
// ---------------------------------------------------------------------------

var serverName    = '${projectName}-${environment}-postgres'
var adminLogin    = 'psqladmin'
var dnsZoneName   = '${serverName}.private.postgres.database.azure.com'

var databases = [
  'auth_db'
  'tracking_db'
  'notifications_db'
  'statistics_db'
]

// ---------------------------------------------------------------------------
// Private DNS Zone — required for Flexible Server VNet integration
// ---------------------------------------------------------------------------

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: dnsZoneName
  location: 'global'
}

resource privateDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: privateDnsZone
  name: '${projectName}-${environment}-vnet-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

// ---------------------------------------------------------------------------
// PostgreSQL Flexible Server
// ---------------------------------------------------------------------------

resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: serverName
  location: location
  sku: {
    name: 'Standard_D2s_v3'
    tier: 'GeneralPurpose'
  }
  properties: {
    administratorLogin: adminLogin
    administratorLoginPassword: adminPassword
    version: '16'

    storage: {
      storageSizeGB: 32
      autoGrow: 'Enabled'
    }

    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }

    highAvailability: {
      mode: 'Disabled'
    }

    // Private-access mode: traffic stays inside the VNet via subnet delegation
    network: {
      delegatedSubnetResourceId: postgresSubnetId
      privateDnsZoneArmResourceId: privateDnsZone.id
    }

    maintenanceWindow: {
      customWindow: 'Enabled'
      dayOfWeek: 0       // Sunday
      startHour: 2
      startMinute: 0
    }
  }

  dependsOn: [
    privateDnsZoneVnetLink
  ]
}

// ---------------------------------------------------------------------------
// Databases
// ---------------------------------------------------------------------------

resource postgresDatabase 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = [
  for dbName in databases: {
    parent: postgresServer
    name: dbName
    properties: {
      charset: 'UTF8'
      collation: 'en_US.utf8'
    }
  }
]

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Fully qualified domain name of the PostgreSQL server.')
output serverFqdn string = postgresServer.properties.fullyQualifiedDomainName

@description('Name of the PostgreSQL server.')
output serverName string = postgresServer.name

@description('Resource ID of the PostgreSQL server.')
output serverId string = postgresServer.id

@description('Administrator login username.')
output adminLogin string = adminLogin
