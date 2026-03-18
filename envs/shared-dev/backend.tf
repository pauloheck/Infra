###############################################################################
# Shared Dev — Backend (state remoto)
# Reutiliza o storage account do BeeAI com chave separada.
###############################################################################

terraform {
  backend "azurerm" {
    resource_group_name  = "rg-beeai-platform"
    storage_account_name = "stbeeaitfstategrw1t4"
    container_name       = "tfstate"
    key                  = "shared-dev/terraform.tfstate"
  }
}
