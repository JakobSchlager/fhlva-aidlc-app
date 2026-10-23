terraform {
  backend "azurerm" {
    resource_group_name  = "fhooe-aidlc-dev-rg"
#    storage_account_name = "fhooeaidlctfstate" # created by scripts/bootstrap-tf-state.sh
    storage_account_name = "skbeerstorage" # created by scripts/bootstrap-tf-state.sh
    container_name       = "tfstate"
    key                  = "dev/terraform.tfstate"
  }
}
