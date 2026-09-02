terraform {
  backend "azurerm" {
    resource_group_name  = "fhooe-aidlc-tfstate-rg"
    storage_account_name = "FILL_IN_STORAGE_ACCOUNT" # created by scripts/bootstrap-tf-state.sh
    container_name       = "tfstate"
    key                  = "staging/terraform.tfstate"
  }
}
