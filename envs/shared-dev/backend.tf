###############################################################################
# Shared Dev — Backend (state remoto)
#
# ⚠️  IMPORTANTE para infra efêmera:
#   O storage account abaixo está em rg-beeai-platform — FORA do rg-shared-dev.
#   "terraform destroy" em shared-dev NÃO destrói este storage.
#   O tfstate sobrevive ao destroy e permite recriar a infra com "apply.sh".
#
#   NÃO delete rg-beeai-platform manualmente.
###############################################################################

terraform {
  backend "azurerm" {
    resource_group_name  = "rg-beeai-platform"
    storage_account_name = "stbeeaitfstategrw1t4"
    container_name       = "tfstate"
    key                  = "shared-dev/terraform.tfstate"
  }
}
