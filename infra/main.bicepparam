// =============================================================================
// main.bicepparam — Example parameter values for the Beer Tracker infrastructure
//
//  IMPORTANT: This file is committed to source control. Sensitive values
//  (all @secure() parameters) MUST be supplied at deployment time via one of:
//
//    a) Azure Key Vault parameter references:
//         adminPassword: az:keyvault('<bootstrap-kv>').secret('postgres-admin-pwd')
//
//    b) Environment variables / CI/CD secret injection:
//         az deployment group create \
//           --parameters @main.bicepparam \
//                        adminPassword="$POSTGRES_ADMIN_PASSWORD" \
//                        authRs256PrivateKey="$AUTH_RSA_PRIVATE_KEY" \
//                        ...
//
//  Never commit actual secret values to this file.
// =============================================================================

using './main.bicep'

// ---------------------------------------------------------------------------
// Core parameters
// ---------------------------------------------------------------------------

param location = 'germanywestcentral'

@description('Short, lowercase identifier for the project. Used as a prefix in all resource names.')
param projectName = 'beertracker'

@description('Deployment target environment.')
param environment = 'dev'

// ---------------------------------------------------------------------------
// Notification settings
// ---------------------------------------------------------------------------

param alertEmailAddress = 'platform-alerts@example.com'

// ---------------------------------------------------------------------------
// Secrets — replace with your CI/CD secret injection mechanism.
// Never store real values in this file.
// ---------------------------------------------------------------------------

// PostgreSQL administrator password (min 8 chars, upper + lower + digit + special)
param adminPassword = 'REPLACE_WITH_SECURE_VALUE'

// RSA-256 private key in PEM format used by auth-service to sign JWTs
param authRs256PrivateKey = 'REPLACE_WITH_SECURE_VALUE'

// Per-service PostgreSQL passwords (each service connects with its own credential)
param authDbPassword         = 'REPLACE_WITH_SECURE_VALUE'
param trackingDbPassword     = 'REPLACE_WITH_SECURE_VALUE'
param notificationsDbPassword = 'REPLACE_WITH_SECURE_VALUE'
param statisticsDbPassword   = 'REPLACE_WITH_SECURE_VALUE'

// Shared HMAC/bearer token used for service-to-service authentication
param internalApiKey = 'REPLACE_WITH_SECURE_VALUE'
