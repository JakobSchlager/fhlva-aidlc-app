<#
.SYNOPSIS
    Tears down and destroys all Azure resources created for Beer Tracker.

.DESCRIPTION
    Quickly deletes the Azure deployment resource group (containing AKS, ACR, App Gateway,
    VNet, and Log Analytics) as described in infra/terraform/README.md Rollback section.
    Optionally deletes the Terraform state resource group and cleans up local variable files.

.PARAMETER ConfigFile
    Path to environment configuration file. Defaults to ./.env.azure.

.PARAMETER DeleteTfState
    Switch to also delete the Terraform remote state resource group and storage account.

.PARAMETER Force
    Skips the confirmation prompt and proceeds with deletion immediately.

.PARAMETER NoWait
    Triggers asynchronous deletion in Azure without waiting for resources to be fully purged.

.NOTES
    Recycled from infra/terraform/README.md Rollback section:
    az group delete --name <deployment-resource-group-name> --yes --no-wait
#>

[CmdletBinding()]
param(
    [string]$ConfigFile = "./.env.azure",
    [switch]$DeleteTfState,
    [switch]$Force,
    [switch]$NoWait
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$ConfigPath = Join-Path $RepoRoot $ConfigFile

# Load configuration if available
$ResourceGroup = ""
$TfStateRg = ""
$SubscriptionId = ""

if (Test-Path $ConfigPath) {
    Get-Content $ConfigPath | ForEach-Object {
        $line = $_.Trim()
        if ($line -and (-not $line.StartsWith("#"))) {
            $parts = $line -split "=", 2
            if ($parts.Length -eq 2) {
                $k = $parts[0].Trim()
                $v = $parts[1].Trim().Trim('"').Trim("'")
                if ($k -eq "AZURE_RESOURCE_GROUP") { $ResourceGroup = $v }
                if ($k -eq "AZURE_TFSTATE_RG") { $TfStateRg = $v }
                if ($k -eq "AZURE_SUBSCRIPTION_ID") { $SubscriptionId = $v }
                if ($k -eq "AZURE_PROJECT_NAME" -and -not $ResourceGroup) { $ResourceGroup = "${v}-dev-rg" }
                if ($k -eq "AZURE_PROJECT_NAME" -and -not $TfStateRg) { $TfStateRg = "${v}-tfstate-rg" }
            }
        }
    }
}

if (-not $ResourceGroup) {
    $ResourceGroup = "fhooe-aidlc-pas-dev-rg"
}
if (-not $TfStateRg) {
    $TfStateRg = "fhooe-aidlc-pas-tfstate-rg"
}

Write-Host "`n============================================================" -ForegroundColor Red
Write-Host "  Beer Tracker - Azure Teardown / Cleanup" -ForegroundColor Red
Write-Host "============================================================" -ForegroundColor Red

Write-Host "Target resources to delete:" -ForegroundColor Yellow
Write-Host "  Resource Group:            $ResourceGroup"
if ($TfStateRg -eq $ResourceGroup) {
    Write-Host "  (Single RG mode: Infrastructure and Terraform state are both in '$ResourceGroup')" -ForegroundColor Gray
} elseif ($DeleteTfState) {
    Write-Host "  Terraform State RG:        $($TfStateRg) [Will be DELETED]" -ForegroundColor Red
} else {
    Write-Host "  Terraform State RG:        $($TfStateRg) [Preserved; use -DeleteTfState to remove]"
}

if (-not $Force) {
    $confirm = Read-Host "`nAre you sure you want to delete these resources? (Type 'yes' to proceed)"
    if ($confirm -ne "yes") {
        Write-Host "Aborted by user." -ForegroundColor Gray
        return
    }
}

if ($SubscriptionId) {
    az account set --subscription $SubscriptionId 2>$null
}

$waitFlag = if ($NoWait) { "--no-wait" } else { "" }

Write-Host "`n==> Deleting Deployment Resource Group '$ResourceGroup'..." -ForegroundColor Cyan
if (((az group exists --name $ResourceGroup).Trim() -eq "true")) {
    if ($NoWait) {
        az group delete --name $ResourceGroup --yes --no-wait
        Write-Host "Deletion initiated in background [no-wait]." -ForegroundColor Green
    } else {
        az group delete --name $ResourceGroup --yes
        Write-Host "Resource Group '$ResourceGroup' deleted." -ForegroundColor Green
    }
} else {
    Write-Host "Resource Group '$ResourceGroup' does not exist." -ForegroundColor Gray
}

if ($DeleteTfState -and ($TfStateRg -ne $ResourceGroup)) {
    Write-Host "`n==> Deleting Terraform State Resource Group '$TfStateRg'..." -ForegroundColor Cyan
    if (((az group exists --name $TfStateRg).Trim() -eq "true")) {
        if ($NoWait) {
            az group delete --name $TfStateRg --yes --no-wait
            Write-Host "State deletion initiated in background [no-wait]." -ForegroundColor Green
        } else {
            az group delete --name $TfStateRg --yes
            Write-Host "Resource Group '$TfStateRg' deleted." -ForegroundColor Green
        }
    } else {
        Write-Host "Resource Group '$TfStateRg' does not exist." -ForegroundColor Gray
    }
}

# Clean up Azure's automatic NetworkWatcherRG if present
if (((az group exists --name "NetworkWatcherRG").Trim() -eq "true")) {
    Write-Host "`n==> Deleting Azure Platform 'NetworkWatcherRG'..." -ForegroundColor Cyan
    if ($NoWait) {
        az group delete --name "NetworkWatcherRG" --yes --no-wait
        Write-Host "NetworkWatcherRG deletion initiated in background [no-wait]." -ForegroundColor Green
    } else {
        az group delete --name "NetworkWatcherRG" --yes
        Write-Host "Resource Group 'NetworkWatcherRG' deleted." -ForegroundColor Green
    }
}

# Clean up local auto tfvars
$AutoVars = Join-Path $RepoRoot "infra/terraform/stages/dev/dev.auto.tfvars.json"
if (Test-Path $AutoVars) {
    Remove-Item $AutoVars -Force
    Write-Host "Cleaned up local dev.auto.tfvars.json." -ForegroundColor Gray
}

Write-Host "`nTeardown completed.`n" -ForegroundColor Green
