// =============================================================================
// monitoring.bicep — Log Analytics Workspace + Azure Monitor alert rules
//
//  This module is designed to be called in two phases from main.bicep:
//
//  Phase 1 (before AKS):  aksClusterId = ''  → workspace created only
//  Phase 2 (after AKS):   aksClusterId = <id> → workspace + alert rules
//
//  ARM incremental mode makes the workspace re-apply idempotent.
// =============================================================================

@description('Azure region for all resources.')
param location string

@description('Project name prefix used for resource naming.')
param projectName string

@description('Environment name (e.g., dev, staging, prod).')
param environment string

@description('Resource ID of the AKS cluster. Leave empty to skip alert-rule creation.')
param aksClusterId string = ''

@description('Resource ID of the Application Gateway. Required for AppGW diagnostic settings when aksClusterId is provided.')
param appGwId string = ''

@description('Email address for alert notifications.')
param alertEmailAddress string = 'platform-alerts@example.com'

// ---------------------------------------------------------------------------
// Variables
// ---------------------------------------------------------------------------

var workspaceName  = '${projectName}-${environment}-law'
var alertsEnabled  = !empty(aksClusterId)

// ---------------------------------------------------------------------------
// Log Analytics Workspace
// ---------------------------------------------------------------------------

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 90
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: 5    // Adjust for production data volumes
    }
  }
}

// ---------------------------------------------------------------------------
// Application Gateway Diagnostic Settings (send access logs to workspace)
// Only provisioned when the full monitoring phase is active.
// ---------------------------------------------------------------------------

resource existingAppGw 'Microsoft.Network/applicationGateways@2024-05-01' existing = if (alertsEnabled && !empty(appGwId)) {
  name: last(split(appGwId, '/'))
}

resource appGwDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (alertsEnabled && !empty(appGwId)) {
  name: 'appgw-to-law'
  scope: existingAppGw
  properties: {
    workspaceId: workspace.id
    logs: [
      {
        category: 'ApplicationGatewayAccessLog'
        enabled: true
      }
      {
        category: 'ApplicationGatewayFirewallLog'
        enabled: false
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Action Group — email notification for all alerts
// ---------------------------------------------------------------------------

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: '${projectName}-${environment}-alerts-ag'
  location: 'global'
  properties: {
    groupShortName: 'BeerAlerts'
    enabled: true
    emailReceivers: [
      {
        name: 'PlatformTeam'
        emailAddress: alertEmailAddress
        useCommonAlertSchema: true
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Alert Rule 1: Pod Restart Rate > 3 in a 5-minute window
//
// Queries Container Insights KubePodInventory table. AGIC and Container
// Insights are required for data to flow into the workspace.
// ---------------------------------------------------------------------------

resource podRestartAlert 'Microsoft.Insights/scheduledQueryRules@2022-06-15' = if (alertsEnabled) {
  name: '${projectName}-${environment}-pod-restarts'
  location: location
  properties: {
    displayName: '[${toUpper(environment)}] Beer Tracker — Pod Restart Count Exceeded'
    description: 'Fires when any pod in the beer-tracker namespace restarts more than 3 times within 5 minutes.'
    severity: 2  // Warning
    enabled: true
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    scopes: [
      workspace.id
    ]
    criteria: {
      allOf: [
        {
          query: '''
            KubePodInventory
            | where TimeGenerated > ago(5m)
            | where Namespace =~ "beer-tracker"
            | where isnotempty(PodRestartCount)
            | summarize MaxRestarts = max(PodRestartCount) by PodName = Name, Namespace, ClusterId
            | where MaxRestarts > 3
          '''
          timeAggregation: 'Count'
          threshold: 0
          operator: 'GreaterThan'
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: alertsEnabled ? [ actionGroup.id ] : []
    }
    autoMitigate: true
    muteActionsDuration: 'PT30M'
  }
}

// ---------------------------------------------------------------------------
// Alert Rule 2: HTTP 5xx Error Rate > 1% over a 2-minute window
//
// Requires Application Gateway access logs flowing into the workspace
// (configured by the appGwDiagnostics resource above).
// ---------------------------------------------------------------------------

resource http5xxAlert 'Microsoft.Insights/scheduledQueryRules@2022-06-15' = if (alertsEnabled) {
  name: '${projectName}-${environment}-http-5xx'
  location: location
  properties: {
    displayName: '[${toUpper(environment)}] Beer Tracker — HTTP 5xx Error Rate Exceeded 1%'
    description: 'Fires when the HTTP 5xx error rate from the Application Gateway exceeds 1% of total requests over a 2-minute window.'
    severity: 1  // Error
    enabled: true
    evaluationFrequency: 'PT1M'
    windowSize: 'PT2M'
    scopes: [
      workspace.id
    ]
    criteria: {
      allOf: [
        {
          query: '''
            AzureDiagnostics
            | where TimeGenerated > ago(2m)
            | where ResourceType == "APPLICATIONGATEWAYS"
            | where Category == "ApplicationGatewayAccessLog"
            | summarize
                TotalRequests  = count(),
                ErrorRequests  = countif(httpStatus_d >= 500)
              by bin(TimeGenerated, 1m)
            | where TotalRequests > 0
            | extend ErrorRatePct = (toreal(ErrorRequests) / toreal(TotalRequests)) * 100.0
            | where ErrorRatePct > 1.0
          '''
          timeAggregation: 'Count'
          threshold: 0
          operator: 'GreaterThan'
          failingPeriods: {
            numberOfEvaluationPeriods: 2
            minFailingPeriodsToAlert: 2
          }
        }
      ]
    }
    actions: {
      actionGroups: alertsEnabled ? [ actionGroup.id ] : []
    }
    autoMitigate: true
    muteActionsDuration: 'PT15M'
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Resource ID of the Log Analytics workspace.')
output workspaceId string = workspace.id

@description('Name of the Log Analytics workspace.')
output workspaceName string = workspace.name

@description('Customer ID (workspace GUID) of the Log Analytics workspace.')
output workspaceCustomerId string = workspace.properties.customerId
