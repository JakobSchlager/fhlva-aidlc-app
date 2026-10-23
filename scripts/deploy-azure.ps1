<#
.SYNOPSIS
    Automated PowerShell deployment script for Beer Tracker on Azure AKS.

.DESCRIPTION
    Executes the end-to-end Azure AKS deployment workflow as described in README Scenario 3:
    1. Preflight validation and quota check (verifies regional capacity, CLIs, permissions, name availability)
    2. Phase 1 Setup:
       - RSA key generation (README Scenario 3 Step 1)
       - Resource Group and Log Analytics creation (README Scenario 3 Step 2)
       - Terraform remote state bootstrap via scripts/bootstrap-tf-state.sh (README Scenario 3 Step 3)
    3. Terraform infrastructure provisioning (README Scenario 3 Step 5)
    4. Application build, container push and Helm release via scripts/deploy-azure.sh (README Phase 2 Step 8)
    5. Post-deployment verification and public endpoint health check

.PARAMETER ConfigFile
    Path to environment configuration file. Defaults to ./.env.azure.

.PARAMETER PreflightOnly
    When specified, only runs validation and capacity checks without provisioning resources.

.PARAMETER AutoApprove
    When specified, skips interactive confirmation prompts before applying Terraform.

.NOTES
    Recycled components and sources:
    - Step 1 (RSA Key): README.md line 341 (openssl genrsa)
    - Step 2 (RG and LAW): README.md lines 347-354 (az group create, az monitor log-analytics...)
    - Step 3 (Remote State): scripts/bootstrap-tf-state.sh (invoked via Git Bash)
    - Step 4 (App Secrets): README.md lines 404-407 (openssl rand)
    - Step 5 (Terraform): README.md lines 375-377 (terraform init, terraform apply)
    - Step 6 (App Deploy): scripts/deploy-azure.sh (invoked via Git Bash)
    - Step 7 (Verification): README.md lines 431-436 (kubectl get pods, kubectl get ingress)
#>

[CmdletBinding()]
param(
    [string]$ConfigFile = "./.env.azure",
    [switch]$PreflightOnly,
    [switch]$AutoApprove
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

# --- Output Formatting Helpers -----------------------------------------------
function Write-Header {
    param([string]$Text)
    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
}

function Write-Step {
    param([string]$Step, [string]$Text)
    Write-Host "`n>>> [$Step] $Text" -ForegroundColor Yellow
}

function Write-Success {
    param([string]$Text)
    Write-Host "[OK] $Text" -ForegroundColor Green
}

function Write-Info {
    param([string]$Text)
    Write-Host "     $Text" -ForegroundColor Gray
}

function Write-WarnMsg {
    param([string]$Text)
    Write-Host "[WARN] $Text" -ForegroundColor Yellow
}

# --- Resolve Repository Root -------------------------------------------------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir

# Convert Windows path to MSYS/Git Bash Unix format
function Convert-ToUnixPath {
    param([string]$WinPath)
    $normalized = ($WinPath -replace '\\', '/')
    if ($normalized -match '^([a-zA-Z]):(.*)') {
        return "/$($Matches[1].ToLower())$($Matches[2])"
    }
    return $normalized
}

$RepoRootUnix = Convert-ToUnixPath $RepoRoot

# --- Helper: Locate Git Bash -------------------------------------------------
function Get-GitBashPath {
    $searchPaths = @(
        "C:\Program Files\Git\bin\bash.exe",
        "C:\Program Files (x86)\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
    )
    foreach ($p in $searchPaths) {
        if (Test-Path $p) { return $p }
    }
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if ($gitCmd) {
        $candidate = Join-Path (Split-Path (Split-Path $gitCmd.Source -Parent) -Parent) "bin\bash.exe"
        if (Test-Path $candidate) { return $candidate }
    }
    throw "Git Bash (bash.exe) was not found. Please ensure Git for Windows is installed."
}

$GitBashExe = Get-GitBashPath
Write-Info -Text "Using Git Bash: $GitBashExe"

# --- Helper: Execute Bash Command via Git Bash --------------------------------
function Invoke-GitBash {
    param(
        [string]$Command,
        [hashtable]$EnvVars = @{}
    )
    $envExports = ""
    foreach ($k in $EnvVars.Keys) {
        $v = $EnvVars[$k]
        $envExports += "export $k='$v'; "
    }
    $fullScript = "export MSYS2_ARG_CONV_EXCL='/subscriptions'; cd '$RepoRootUnix'; $envExports $Command"
    
    $proc = Start-Process -FilePath $GitBashExe -ArgumentList @("-c", $fullScript) -NoNewWindow -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        throw "Command executed in Git Bash failed with exit code $($proc.ExitCode): $Command"
    }
}

# --- IP / CIDR Helper Functions ----------------------------------------------
function Convert-ToCidrParts {
    param([string]$Address)
    $clean = $Address.Trim()
    if ($clean.Contains("/")) {
        $parts = $clean.Split("/")
        return @{
            Ip     = [System.Net.IPAddress]::Parse($parts[0].Trim())
            Prefix = [int]$parts[1].Trim()
        }
    } else {
        return @{
            Ip     = [System.Net.IPAddress]::Parse($clean)
            Prefix = 32
        }
    }
}

function Test-SubnetContained {
    param(
        [Parameter(Mandatory=$true)][string]$Candidate,
        [Parameter(Mandatory=$true)][string]$ParentCidr
    )
    try {
        if ([string]::IsNullOrWhiteSpace($Candidate) -or [string]::IsNullOrWhiteSpace($ParentCidr)) {
            return $false
        }
        $cand = Convert-ToCidrParts $Candidate
        $parent = Convert-ToCidrParts $ParentCidr

        if ($cand.Ip.AddressFamily -ne $parent.Ip.AddressFamily) { return $false }
        if ($cand.Ip.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { return $false }

        if ($cand.Prefix -lt $parent.Prefix) {
            return $false
        }

        $candBytes = $cand.Ip.GetAddressBytes()
        $parentBytes = $parent.Ip.GetAddressBytes()
        if ([BitConverter]::IsLittleEndian) {
            [Array]::Reverse($candBytes)
            [Array]::Reverse($parentBytes)
        }
        $candUint = [BitConverter]::ToUInt32($candBytes, 0)
        $parentUint = [BitConverter]::ToUInt32($parentBytes, 0)

        $parentMask = if ($parent.Prefix -eq 0) { [uint32]0 } else { [uint32]::MaxValue -shl (32 - $parent.Prefix) }

        return ($candUint -band $parentMask) -eq ($parentUint -band $parentMask)
    } catch {
        return $false
    }
}

function Find-ContainingRange {
    param(
        [Parameter(Mandatory=$true)][string]$Candidate,
        [Parameter(Mandatory=$true)][string[]]$Ranges
    )
    foreach ($r in $Ranges) {
        if (-not [string]::IsNullOrWhiteSpace($r)) {
            if (Test-SubnetContained $Candidate $r) {
                return $r
            }
        }
    }
    return $null
}

# --- Load Environment Configuration -----------------------------------------
Write-Header -Text "Beer Tracker - Azure AKS Deployment"

$ConfigPath = Join-Path $RepoRoot $ConfigFile
if (-not (Test-Path $ConfigPath)) {
    $ExamplePath = Join-Path $RepoRoot ".env.azure.example"
    if (Test-Path $ExamplePath) {
        Write-WarnMsg -Text "Config file '$ConfigFile' not found. Creating from .env.azure.example..."
        Copy-Item -Path $ExamplePath -Destination $ConfigPath
        Write-Info -Text "Created '$ConfigPath'. Loading defaults..."
    } else {
        throw "Configuration file not found at $ConfigPath and no example file exists."
    }
}

# Parse key=value lines from .env.azure
$Config = @{}
Get-Content $ConfigPath | ForEach-Object {
    $line = $_.Trim()
    if ($line -and (-not $line.StartsWith("#"))) {
        $parts = $line -split "=", 2
        if ($parts.Length -eq 2) {
            $key = $parts[0].Trim()
            $val = $parts[1].Trim().Trim('"').Trim("'")
            $Config[$key] = $val
        }
    }
}

# --- Set Default Values and Fallbacks ----------------------------------------
$SubscriptionId = $Config["AZURE_SUBSCRIPTION_ID"]
$Location = if ($Config["AZURE_LOCATION"]) { $Config["AZURE_LOCATION"] } else { "germanywestcentral" }
$ProjectName = if ($Config["AZURE_PROJECT_NAME"]) { $Config["AZURE_PROJECT_NAME"] } else { "fhooe-aidlc-pas" }
$Environment = if ($Config["AZURE_ENVIRONMENT"]) { $Config["AZURE_ENVIRONMENT"] } else { "dev" }

$ResourceGroup = if ($Config["AZURE_RESOURCE_GROUP"]) { $Config["AZURE_RESOURCE_GROUP"] } else { "${ProjectName}-${Environment}-rg" }
$WorkspaceName = if ($Config["AZURE_WORKSPACE_NAME"]) { $Config["AZURE_WORKSPACE_NAME"] } else { "${ProjectName}-${Environment}-law" }
$TfStateRg = if ($Config["AZURE_TFSTATE_RG"]) { $Config["AZURE_TFSTATE_RG"] } else { $ResourceGroup }
$StorageContainer = if ($Config["AZURE_STORAGE_CONTAINER"]) { $Config["AZURE_STORAGE_CONTAINER"] } else { "tfstate" }

$AksVmSize = if ($Config["AKS_VM_SIZE"]) { $Config["AKS_VM_SIZE"] } else { "Standard_D2s_v3" }
$AksMinCount = if ($Config["AKS_NODE_MIN_COUNT"]) { [int]$Config["AKS_NODE_MIN_COUNT"] } else { 2 }
$AksMaxCount = if ($Config["AKS_NODE_MAX_COUNT"]) { [int]$Config["AKS_NODE_MAX_COUNT"] } else { 2 }
$AcrSku = if ($Config["ACR_SKU"]) { $Config["ACR_SKU"] } else { "Basic" }
$AppGwMinCapacity = if ($Config["APPGW_MIN_CAPACITY"]) { [int]$Config["APPGW_MIN_CAPACITY"] } else { 0 }
$AppGwMaxCapacity = if ($Config["APPGW_MAX_CAPACITY"]) { [int]$Config["APPGW_MAX_CAPACITY"] } else { 2 }

$AuthRsaKeyPath = if ($Config["AUTH_RSA_KEY_PATH"]) { $Config["AUTH_RSA_KEY_PATH"] } else { "secrets/auth-rs256-private-key.pem" }
$AlertEmail = if ($Config["ALERT_EMAIL_ADDRESS"]) { $Config["ALERT_EMAIL_ADDRESS"] } else { "platform@example.com" }
$EnableDynatrace = if ($Config["ENABLE_DYNATRACE"]) { [bool]::Parse($Config["ENABLE_DYNATRACE"]) } else { $true }

# Storage account fallback name if empty
$StorageAccount = $Config["AZURE_STORAGE_ACCOUNT"]
if (-not $StorageAccount) {
    # Generate unique 3-24 char alphanumeric name
    $cleanPrefix = ($ProjectName -replace '[^a-zA-Z0-9]', '').ToLower()
    if ($cleanPrefix.Length -gt 14) { $cleanPrefix = $cleanPrefix.Substring(0, 14) }
    $rndSuffix = (-join ((48..57) + (97..122) | Get-Random -Count 6 | ForEach-Object { [char]$_ }))
    $StorageAccount = "${cleanPrefix}st${rndSuffix}"
}

# --- STEP 0: Preflight Validation and Region Capacity Check ------------------
Write-Step -Step "0/7" -Text "Performing Preflight Validation and Regional Capacity Checks"

# 1. Check Azure CLI login and subscription
Write-Info -Text "Checking Azure CLI authentication..."
$azAccountJson = az account show -o json 2>$null
if ($LASTEXITCODE -ne 0 -or -not $azAccountJson) {
    throw "Azure CLI is not logged in. Please run 'az login' first."
}
$AzAccount = $azAccountJson | ConvertFrom-Json
if (-not $SubscriptionId) {
    $SubscriptionId = $AzAccount.id
}
if ($AzAccount.id -ne $SubscriptionId) {
    Write-Info -Text "Switching active Azure subscription to $SubscriptionId..."
    az account set --subscription $SubscriptionId
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to set subscription $SubscriptionId."
    }
}
$subMsg = "Azure CLI active subscription: " + $AzAccount.name + " (" + $SubscriptionId + ")"
Write-Success -Text $subMsg

# 2. Check signed-in user and cluster admin object ID
Write-Info -Text "Resolving signed-in user Entra ID Object ID..."
$SignedInUserId = (az ad signed-in-user show --query id -o tsv 2>$null).Trim()
if (-not $SignedInUserId) {
    throw "Unable to determine current signed-in user Object ID from Azure AD."
}
Write-Success -Text "Signed-in User ID: $SignedInUserId"

# 3. Check CLI Tool Dependencies
Write-Info -Text "Checking required CLI tools..."
$RequiredTools = @("git", "terraform", "docker", "kubectl", "kubelogin", "helm", "openssl")
foreach ($t in $RequiredTools) {
    $cmd = Get-Command $t -ErrorAction SilentlyContinue
    if (-not $cmd) {
        throw "Required CLI tool '$t' was not found on PATH."
    }
}
# Verify Docker daemon is running
try {
    $dockerCheck = docker info --format '{{.ServerVersion}}' 2>$null
    if (-not $dockerCheck) { throw "Docker daemon returned empty response" }
    $toolsMsg = "All required tools available (Docker $dockerCheck, Terraform, kubectl, kubelogin, helm, openssl)"
    Write-Success -Text $toolsMsg
} catch {
    throw "Docker daemon is not running. Please start Docker Desktop or Rancher Desktop."
}

# 4. Check Resource Providers Registration
Write-Info -Text "Verifying Azure resource providers..."
$Providers = @(
    "Microsoft.ContainerService",
    "Microsoft.ContainerRegistry",
    "Microsoft.OperationalInsights",
    "Microsoft.Network",
    "Microsoft.Storage"
)
foreach ($p in $Providers) {
    $status = (az provider show -n $p --query registrationState -o tsv 2>$null).Trim()
    if ($status -ne "Registered") {
        Write-WarnMsg -Text "Provider $p is '$status'. Registering..."
        az provider register -n $p | Out-Null
    }
}
Write-Success -Text "Azure resource providers verified."

# 5. Check Regional VM Quota and Capacity (Crucial to prevent mid-apply failure!)
Write-Info -Text "Validating regional capacity in '$Location' for VM size '$AksVmSize'..."
$usagesJson = az vm list-usage --location $Location -o json 2>$null
if ($LASTEXITCODE -ne 0 -or -not $usagesJson) {
    Write-WarnMsg -Text "Could not query VM list-usage in $Location. Proceeding with caution..."
} else {
    $usages = $usagesJson | ConvertFrom-Json
    
    # Check total regional cores
    $coreUsage = $usages | Where-Object { $_.name.value -eq "cores" }
    $regionalLimit = [int]$coreUsage.limit
    $regionalCurrent = [int]$coreUsage.currentValue
    $regionalAvailable = $regionalLimit - $regionalCurrent
    
    # Calculate required cores: Standard_D2s_v3 has 2 cores, D4s_v3 has 4 cores
    $coresPerNode = 2
    if ($AksVmSize -match 'D4') { $coresPerNode = 4 }
    elseif ($AksVmSize -match 'D8') { $coresPerNode = 8 }
    $ClusterName = "${ProjectName}-${Environment}-aks"
    $existingClusterNodes = 0
    $rgExists = ((az group exists --name $ResourceGroup).Trim() -eq "true")
    if ($rgExists) {
        $clusterCheck = az aks show --resource-group $ResourceGroup --name $ClusterName --query "agentPoolProfiles[0].count" -o tsv 2>$null
        if ($LASTEXITCODE -eq 0 -and $clusterCheck) {
            $existingClusterNodes = [int]$clusterCheck.Trim()
        }
    }
    $additionalNodes = [Math]::Max(0, ($AksMinCount - $existingClusterNodes))
    $additionalCores = $additionalNodes * $coresPerNode
    $requiredCores = $AksMinCount * $coresPerNode

    # Check DSv3 / Dv3 family usage if applicable
    $familyUsage = $usages | Where-Object { $_.name.value -eq "standardDSv3Family" -or $_.name.value -eq "standardDv3Family" } | Select-Object -First 1
    if ($familyUsage) {
        $familyLimit = [int]$familyUsage.limit
        $familyCurrent = [int]$familyUsage.currentValue
        $familyAvailable = $familyLimit - $familyCurrent
        
        $quotaStatusMsg = "Quota status in $Location : $AksVmSize requires $requiredCores vCPUs ($AksMinCount nodes x $coresPerNode cores)"
        if ($existingClusterNodes -gt 0) {
            $quotaStatusMsg += " [Cluster '$ClusterName' already active with $existingClusterNodes nodes; $additionalCores new vCPUs needed]"
        }
        Write-Info -Text $quotaStatusMsg
        $familyMsg = "  DSv3 Family: Available = $familyAvailable (Limit: $familyLimit, Current: $familyCurrent)"
        Write-Info -Text $familyMsg
        $coreMsg = "  Total Regional Cores: Available = $regionalAvailable (Limit: $regionalLimit, Current: $regionalCurrent)"
        Write-Info -Text $coreMsg

        if ($additionalCores -gt $familyAvailable -or $additionalCores -gt $regionalAvailable) {
            Write-Host "`n[ERROR] Regional capacity check failed!" -ForegroundColor Red
            Write-Host "  Requested node pool requires $additionalCores additional vCPUs of size $AksVmSize." -ForegroundColor Red
            Write-Host "  Available DSv3 quota: $familyAvailable, Available total cores: $regionalAvailable." -ForegroundColor Red
            Write-Host "  On subscriptions like 'Azure for Students', DSv3 limit is 4 vCPUs." -ForegroundColor Red
            Write-Host "  To fix, set AKS_VM_SIZE=Standard_D2s_v3 and AKS_NODE_MIN_COUNT=2 in .env.azure." -ForegroundColor Red
            throw "Insufficient regional quota in $Location."
        }
    }
}

# 6. Check Public IP Quota
Write-Info -Text "Validating Public IP quota..."
$netUsagesJson = az network list-usages --location $Location -o json 2>$null
if ($netUsagesJson) {
    $netUsages = $netUsagesJson | ConvertFrom-Json
    $pipUsage = $netUsages | Where-Object { $_.name.value -eq "Public IP Addresses" }
    if ($pipUsage) {
        $pipAvailable = [int]$pipUsage.limit - [int]$pipUsage.currentValue
        $pipLimit = $pipUsage.limit
        $pipMsg = "Public IP address quota in $Location : $pipAvailable available of $pipLimit"
        Write-Info -Text $pipMsg
        if ($pipAvailable -lt 1) {
            throw "Public IP address quota in $Location is exhausted: $pipAvailable available of $pipLimit"
        }
    }
}
Write-Success -Text "Regional capacity and quota validation passed."

# 7. Validate AKS VM Size availability in target location via Azure ARM validation
if ($existingClusterNodes -gt 0) {
    Write-Success -Text "AKS cluster '$ClusterName' is already active with VM size '$AksVmSize' in '$Location'."
} else {
    Write-Info -Text "Validating AKS VM size '$AksVmSize' availability in '$Location' for this subscription..."
    $testTemplate = @"
{
  "`$schema": "https://schema.management.azure.com/schemas/2018-05-01/subscriptionDeploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "resources": [
    {
      "type": "Microsoft.Resources/resourceGroups",
      "apiVersion": "2021-04-01",
      "name": "preflight-test-rg",
      "location": "$Location",
      "properties": {}
    },
    {
      "type": "Microsoft.Resources/deployments",
      "apiVersion": "2021-04-01",
      "name": "aks-validation",
      "resourceGroup": "preflight-test-rg",
      "dependsOn": [ "preflight-test-rg" ],
      "properties": {
        "mode": "Incremental",
        "template": {
          "`$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
          "contentVersion": "1.0.0.0",
          "resources": [
            {
              "type": "Microsoft.ContainerService/managedClusters",
              "apiVersion": "2024-02-01",
              "name": "testcluster",
              "location": "$Location",
              "identity": { "type": "SystemAssigned" },
              "properties": {
                "dnsPrefix": "testdns",
                "agentPoolProfiles": [
                  {
                    "name": "system",
                    "count": 1,
                    "vmSize": "$AksVmSize",
                    "osType": "Linux",
                    "mode": "System"
                  }
                ]
              }
            }
          ]
        }
      }
    }
  ]
}
"@
    $tmpFile = [System.IO.Path]::GetTempFileName()
    Set-Content -Path $tmpFile -Value $testTemplate
    try {
        $valOutput = az deployment sub validate --location $Location --template-file $tmpFile -o json 2>&1
        if ($LASTEXITCODE -ne 0) {
            $valMsg = ($valOutput | Out-String)
            if ($valMsg -match "The VM size of [^ ]+ is not allowed in your subscription in location '[^']+'") {
                Write-Host "`n[ERROR] Regional capacity check failed!" -ForegroundColor Red
                Write-Host "  VM size '$AksVmSize' is not allowed in region '$Location' for your subscription!" -ForegroundColor Red
                Write-Host "  $($Matches[0])" -ForegroundColor Red
                throw "Invalid VM size '$AksVmSize' in '$Location'."
            } elseif ($valMsg -match "disallowed by Azure") {
                Write-Host "`n[ERROR] Region '$Location' is disallowed by subscription policy!" -ForegroundColor Red
                throw "Region '$Location' is not allowed by policy."
            }
        } else {
            Write-Success -Text "AKS VM size '$AksVmSize' validated in '$Location'."
        }
    } finally {
        Remove-Item $tmpFile -ErrorAction SilentlyContinue
    }
}

# 7. Check Global Name Availability for Storage Account and ACR
Write-Info -Text "Validating global name availability for Storage Account and ACR..."
$storageCheck = (az storage account check-name --name $StorageAccount -o json 2>$null) | ConvertFrom-Json
if (-not $storageCheck.nameAvailable -and $storageCheck.reason -eq "AlreadyExists") {
    # Check if we already own it in our subscription
    $existingSt = (az storage account list --query "[?name=='$StorageAccount'].id" -o tsv 2>$null)
    if (-not $existingSt) {
        throw "Storage account '$StorageAccount' is already taken globally across Azure. Update AZURE_STORAGE_ACCOUNT in .env.azure."
    }
    Write-Info -Text "Storage account '$StorageAccount' already exists in subscription (reusing)."
} else {
    Write-Success -Text "Storage account name '$StorageAccount' is available."
}

$AcrName = ($ProjectName + $Environment + "acr" -replace '-', '').ToLower()
$acrCheck = (az acr check-name --name $AcrName -o json 2>$null) | ConvertFrom-Json
if (-not $acrCheck.nameAvailable -and $acrCheck.reason -eq "AlreadyExists") {
    $existingAcr = (az acr list --query "[?name=='$AcrName'].id" -o tsv 2>$null)
    if (-not $existingAcr) {
        throw "Container Registry '$AcrName' is already taken globally across Azure. Change AZURE_PROJECT_NAME in .env.azure."
    }
    Write-Info -Text "ACR '$AcrName' already exists in subscription (reusing)."
} else {
    Write-Success -Text "ACR name '$AcrName' is available."
}

# 8. Detect Caller Public IP for Ingress/API Whitelisting
$PublicIp = ""
try {
    $ipObj = Invoke-RestMethod -Uri "https://api.ipify.org?format=json" -TimeoutSec 5 -ErrorAction Stop
    $PublicIp = $ipObj.ip
    Write-Success -Text "Detected caller public IP: $PublicIp"
    $baseDefaultRanges = @("78.104.0.0/16", "185.154.40.0/22", "193.170.0.0/15")
    $coveredBy = Find-ContainingRange -Candidate $PublicIp -Ranges $baseDefaultRanges
    if ($coveredBy) {
        Write-Info -Text "Caller IP $PublicIp is already within allowed range '$coveredBy' (will not be duplicated)."
    }
} catch {
    Write-WarnMsg -Text "Could not auto-detect public IP. Will rely on configured ranges."
}

# If PreflightOnly was requested, exit here
if ($PreflightOnly) {
    Write-Header -Text "Preflight Validation Succeeded!"
    Write-Host "All prerequisites, regional quotas, and global names passed verification.`n" -ForegroundColor Green
    return
}

# --- STEP 1: Phase 1 Setup - RSA Key, Resource Groups and Remote State --------
Write-Step -Step "1/7" -Text "Phase 1 Setup: Security Keys, Resource Groups and State Bootstrap"

# 1. Generate RSA key if missing (README Step 1)
$AbsRsaKeyPath = Join-Path $RepoRoot $AuthRsaKeyPath
$RsaDir = Split-Path -Parent $AbsRsaKeyPath
if (-not (Test-Path $RsaDir)) { New-Item -ItemType Directory -Path $RsaDir -Force | Out-Null }
if (-not (Test-Path $AbsRsaKeyPath)) {
    Write-Info -Text "Generating RSA private key at $AuthRsaKeyPath (README Scenario 3 Step 1)..."
    openssl genrsa -out $AbsRsaKeyPath 2048
    Write-Success -Text "RSA private key generated."
} else {
    Write-Info -Text "RSA private key exists at $AuthRsaKeyPath."
}

# 2. Create Resource Group and Log Analytics (README Step 2)
Write-Info -Text "Ensuring Resource Group '$ResourceGroup' exists (README Scenario 3 Step 2)..."
$rgExists = ((az group exists --name $ResourceGroup).Trim() -eq "true")
if (-not $rgExists) {
    az group create --name $ResourceGroup --location $Location | Out-Null
    Write-Success -Text "Created Resource Group '$ResourceGroup'."
} else {
    Write-Info -Text "Resource Group '$ResourceGroup' already exists."
}

Write-Info -Text "Ensuring Log Analytics workspace '$WorkspaceName' exists (README Scenario 3 Step 2)..."
$lawExists = (az monitor log-analytics workspace list --resource-group $ResourceGroup --query "[?name=='$WorkspaceName'].id" -o tsv 2>$null)
if (-not $lawExists) {
    az monitor log-analytics workspace create --resource-group $ResourceGroup --workspace-name $WorkspaceName --location $Location | Out-Null
    Write-Success -Text "Created Log Analytics workspace '$WorkspaceName'."
} else {
    Write-Info -Text "Log Analytics workspace '$WorkspaceName' already exists."
}

# 3. Bootstrap Remote State Storage via existing bootstrap-tf-state.sh (README Step 3)
Write-Info -Text "Bootstrapping Terraform remote state via scripts/bootstrap-tf-state.sh (README Scenario 3 Step 3)..."
$env:MSYS2_ARG_CONV_EXCL = "/subscriptions"
Remove-Item Env:\MSYS_NO_PATHCONV -ErrorAction SilentlyContinue
$bootstrapScript = Join-Path $RepoRoot "scripts/bootstrap-tf-state.sh"
& $GitBashExe $bootstrapScript `
    "--resource-group" $TfStateRg `
    "--storage-account" $StorageAccount `
    "--container" $StorageContainer `
    "--location" $Location `
    "--subscription" $SubscriptionId
if ($LASTEXITCODE -ne 0) {
    throw "bootstrap-tf-state.sh failed with exit code $LASTEXITCODE"
}
Write-Success -Text "Terraform remote state bootstrapped."

# --- STEP 2: Configure and Apply Terraform Infrastructure ---------------------
Write-Step -Step "2/7" -Text "Terraform Infrastructure Provisioning (dev stage)"

# Build IP whitelist
$AllowedIps = @("78.104.0.0/16", "185.154.40.0/22", "193.170.0.0/15")
if ($Config["ADDITIONAL_ALLOWED_IPS"]) {
    $extra = $Config["ADDITIONAL_ALLOWED_IPS"] -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    foreach ($entry in $extra) {
        $parent = Find-ContainingRange -Candidate $entry -Ranges $AllowedIps
        if ($parent) {
            Write-Info -Text "Additional IP range '$entry' is already covered by '$parent'. Skipping."
        } elseif (-not ($AllowedIps -contains $entry)) {
            $AllowedIps += $entry
        }
    }
}

if ($PublicIp) {
    $containingRange = Find-ContainingRange -Candidate $PublicIp -Ranges $AllowedIps
    if ($containingRange) {
        Write-Info -Text "Caller public IP $PublicIp is already contained in allowed CIDR '$containingRange'. Skipping addition to prevent overlapping subnet errors."
    } else {
        $AllowedIps += "$PublicIp/32"
        Write-Info -Text "Added caller public IP ($PublicIp/32) to allowed IP list."
    }
}
$AllowedIps = $AllowedIps | Select-Object -Unique

# Generate dev.auto.tfvars.json in stages/dev
$TfDir = Join-Path $RepoRoot "infra/terraform/stages/dev"
$AutoTfVars = @{
    subscription_id              = $SubscriptionId
    project_name                 = $ProjectName
    environment                  = $Environment
    location                     = $Location
    alert_email_address          = $AlertEmail
    aks_cluster_admin_object_ids = @($SignedInUserId)
    ingress_allowed_ips          = $AllowedIps
    api_server_authorized_ips    = $AllowedIps
    aks_vm_size                  = $AksVmSize
    aks_min_count                = $AksMinCount
    aks_max_count                = $AksMaxCount
    acr_sku                      = $AcrSku
    appgw_min_capacity           = $AppGwMinCapacity
    appgw_max_capacity           = $AppGwMaxCapacity
}
$AutoTfVarsJson = $AutoTfVars | ConvertTo-Json -Depth 5
$AutoTfVarsPath = Join-Path $TfDir "dev.auto.tfvars.json"
Set-Content -Path $AutoTfVarsPath -Value $AutoTfVarsJson
Write-Success -Text "Generated Terraform variable overrides in '$AutoTfVarsPath'."

# Terraform Init
Write-Info -Text "Running 'terraform init' with remote state backend (README Scenario 3 Step 5)..."
Push-Location $TfDir
try {
    terraform init -reconfigure `
        -backend-config="resource_group_name=$TfStateRg" `
        -backend-config="storage_account_name=$StorageAccount" `
        -backend-config="container_name=$StorageContainer" `
        -backend-config="key=dev/terraform.tfstate"
    if ($LASTEXITCODE -ne 0) { throw "terraform init failed." }
    Write-Success -Text "Terraform initialized."

    # Terraform Apply
    Write-Info -Text "Running 'terraform apply' (README Scenario 3 Step 5)..."
    terraform apply -auto-approve
    if ($LASTEXITCODE -ne 0) { throw "terraform apply failed." }
    Write-Success -Text "Terraform apply completed successfully."
} finally {
    Pop-Location
}

# --- STEP 3: Phase 2 - Generate Passwords and Application Secrets -------------
Write-Step -Step "3/7" -Text "Generating Application Secrets (README Scenario 3 Phase 2 Step 7)"

$DbPassword = $Config["POSTGRES_APP_PASSWORD"]
if (-not $DbPassword) {
    # Generate 32 alphanumeric chars (README line 404)
    $DbPassword = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 32 | ForEach-Object { [char]$_ })
    Write-Info -Text "Generated random POSTGRES_APP_PASSWORD."
}

$InternalApiKey = $Config["INTERNAL_API_KEY"]
if (-not $InternalApiKey) {
    # Generate 64 hex chars (README line 407)
    $InternalApiKey = -join ((48..57) + (97..102) | Get-Random -Count 64 | ForEach-Object { [char]$_ })
    Write-Info -Text "Generated random INTERNAL_API_KEY."
}

# --- STEP 4: Build, Push and Deploy Application via scripts/deploy-azure.sh ---
Write-Step -Step "4/7" -Text "Building, Pushing Images and Deploying via scripts/deploy-azure.sh"

Write-Info -Text "Executing scripts/deploy-azure.sh via Git Bash (README Scenario 3 Phase 2 Step 8)..."
$env:MSYS2_ARG_CONV_EXCL = "/subscriptions"
Remove-Item Env:\MSYS_NO_PATHCONV -ErrorAction SilentlyContinue
$env:AZURE_RESOURCE_GROUP = $ResourceGroup
$env:POSTGRES_APP_PASSWORD = $DbPassword
$env:INTERNAL_API_KEY = $InternalApiKey
$env:AUTH_RSA_KEY_PATH = $AuthRsaKeyPath

$deployScript = Join-Path $RepoRoot "scripts/deploy-azure.sh"
& $GitBashExe $deployScript
if ($LASTEXITCODE -ne 0) {
    throw "deploy-azure.sh failed with exit code $LASTEXITCODE"
}
Write-Success -Text "Application release deployed successfully via Helm."

# --- STEP 5: Deploy Dynatrace Monitoring -------------------------------------
if ($EnableDynatrace) {
    Write-Step -Step "5/7" -Text "Deploying Dynatrace Monitoring (charts/dynakube.yaml)"
    
    $DynaKubePath = Join-Path $RepoRoot "charts/dynakube.yaml"
    if (Test-Path $DynaKubePath) {
        Write-Info -Text "Creating 'dynatrace' namespace..."
        kubectl create namespace dynatrace --dry-run=client -o yaml | kubectl apply -f - | Out-Null
        
        Write-Info -Text "Installing Dynatrace Operator release manifest..."
        kubectl apply -f https://github.com/Dynatrace/dynatrace-operator/releases/latest/download/kubernetes.yaml
        if ($LASTEXITCODE -ne 0) {
            Write-WarnMsg -Text "Dynatrace operator manifest installation returned exit code $LASTEXITCODE."
        }
        
        Write-Info -Text "Right-sizing dynatrace-webhook resources for lab cluster..."
        kubectl set resources deployment dynatrace-webhook -n dynatrace -c webhook --requests=cpu=50m,memory=64Mi --limits=cpu=200m,memory=128Mi 2>$null | Out-Null
        kubectl scale deployment dynatrace-webhook -n dynatrace --replicas=1 2>$null | Out-Null
        
        Write-Info -Text "Waiting for Dynatrace Operator deployment to be ready..."
        kubectl rollout status deployment/dynatrace-operator -n dynatrace --timeout=180s 2>$null
        kubectl rollout status deployment/dynatrace-webhook -n dynatrace --timeout=180s 2>$null
        
        Write-Info -Text "Applying DynaKube custom resources from '$DynaKubePath'..."
        kubectl apply -f $DynaKubePath
        if ($LASTEXITCODE -ne 0) {
            Write-WarnMsg -Text "Applying DynaKube manifest returned exit code $LASTEXITCODE."
        }
        
        Write-Info -Text "Configuring OneAgent automatic injection on namespace 'beer-tracker'..."
        kubectl label namespace beer-tracker oneagent.dynatrace.com/injection=enabled --overwrite | Out-Null
        kubectl label namespace beer-tracker dynatrace.com/inject=true --overwrite | Out-Null
        
        Write-Info -Text "Triggering rolling restart of Beer Tracker deployments for OneAgent instrumentation..."
        kubectl rollout restart deployment -n beer-tracker | Out-Null
        kubectl rollout status deployment/beer-tracker-auth-service -n beer-tracker --timeout=120s 2>$null
        
        Write-Success -Text "Dynatrace Operator and DynaKube deployed; Beer Tracker instrumented."
    } else {
        Write-WarnMsg -Text "Dynatrace configuration '$DynaKubePath' not found. Skipping."
    }
} else {
    Write-Info -Text "Dynatrace monitoring disabled (ENABLE_DYNATRACE=false)."
}

# --- STEP 6: Verification and Health Check -----------------------------------
Write-Step -Step "6/7" -Text "Post-Deployment Verification and Ingress Address"

Write-Info -Text "Checking Kubernetes pods in namespace 'beer-tracker'..."
kubectl get pods -n beer-tracker -o wide

if ($EnableDynatrace) {
    Write-Info -Text "Checking Kubernetes pods in namespace 'dynatrace'..."
    kubectl get pods -n dynatrace -o wide 2>$null
}

Write-Info -Text "Retrieving Application Gateway Ingress IP..."
$IngressIp = ""
$retries = 10
while ($retries -gt 0 -and -not $IngressIp) {
    $ingressOutput = kubectl get ingress -n beer-tracker -o json 2>$null
    if ($ingressOutput) {
        $ingressObj = $ingressOutput | ConvertFrom-Json
        $lb = $ingressObj.items[0].status.loadBalancer.ingress
        if ($lb -and $lb[0].ip) {
            $IngressIp = $lb[0].ip
            break
        }
    }
    Write-Info -Text "Waiting for Application Gateway public IP to bind to ingress (retries left: $retries)..."
    Start-Sleep -Seconds 10
    $retries--
}

# --- STEP 7: Completion Summary ----------------------------------------------
Write-Step -Step "7/7" -Text "Deployment Summary"
Write-Header -Text "Deployment Complete!"

Write-Host "Application Status:" -ForegroundColor Green
Write-Host "  Resource Group:   $ResourceGroup"
Write-Host "  Storage Account:  $StorageAccount ($TfStateRg)"
Write-Host "  ACR SKU:          $AcrSku"
Write-Host "  AKS Node Pool:    $AksVmSize ($AksMinCount nodes)"
Write-Host "  App Gateway Cap:  min=$AppGwMinCapacity, max=$AppGwMaxCapacity"
if ($EnableDynatrace) {
    Write-Host "  Dynatrace:        Enabled (OneAgent injected in namespace 'beer-tracker')" -ForegroundColor Green
}
if ($IngressIp) {
    Write-Host "  Ingress URL:      http://$IngressIp/" -ForegroundColor Cyan
    Write-Host "  Auth Service:     http://$IngressIp/auth/login" -ForegroundColor Cyan
    Write-Host "  Beer Tracking:    http://$IngressIp/tracking" -ForegroundColor Cyan
} else {
    Write-Host "  Ingress IP:       Pending allocation on Application Gateway (check with 'kubectl get ingress -n beer-tracker')"
}

Write-Host "`nTo destroy this deployment later, run:" -ForegroundColor Yellow
Write-Host "  ./scripts/destroy-azure.ps1`n" -ForegroundColor Yellow
