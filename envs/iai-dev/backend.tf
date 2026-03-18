###############################################################################
# IAI Dev — Backend (state remoto compartilhado)
# Usa o mesmo Storage Account da plataforma _heck.
###############################################################################

terraform {
  backend "azurerm" {
    resource_group_name  = "rg-beeai-platform"
    storage_account_name = "stbeeaitfstategrw1t4"
    container_name       = "tfstate"
    key                  = "iai-dev/terraform.tfstate"
  }
}
