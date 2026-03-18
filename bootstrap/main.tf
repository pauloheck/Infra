###############################################################################
# Bootstrap — Plataforma _heck
#
# Cria a fundação necessária antes de qualquer ambiente:
#   - rg-heck-platform        Resource Group da plataforma
#   - sthecktfstate<suffix>   Storage Account para tfstate de todos os envs
#   - tfstate container       Container privado
#   - law-heck-central        Log Analytics central (90 dias)
#
# Executar 1x:
#   az login && terraform init && terraform apply
###############################################################################

terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
}

# ---------- variáveis -------------------------------------------------------
variable "location" {
  default = "eastus2"
}

variable "tags" {
  type = map(string)
  default = {
    project   = "heck-platform"
    managedBy = "terraform-bootstrap"
  }
}

# ---------- random suffix para storage account único --------------------------
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# ---------- Resource Group plataforma ----------------------------------------
resource "azurerm_resource_group" "platform" {
  name     = "rg-heck-platform"
  location = var.location
  tags     = var.tags
}

# ---------- Storage Account para tfstate (todos os projetos _heck) -----------
resource "azurerm_storage_account" "tfstate" {
  name                     = "sthecktfstate${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.platform.name
  location                 = azurerm_resource_group.platform.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
  min_tls_version          = "TLS1_2"

  blob_properties {
    versioning_enabled = true
  }

  tags = var.tags
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.tfstate.name
  container_access_type = "private"
}

# ---------- Log Analytics central (activity logs, alertas de plataforma) ------
resource "azurerm_log_analytics_workspace" "central" {
  name                = "law-heck-central"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  sku                 = "PerGB2018"
  retention_in_days   = 90
  tags                = var.tags
}

# ---------- Outputs -----------------------------------------------------------
output "resource_group_name" {
  value = azurerm_resource_group.platform.name
}

output "storage_account_name" {
  value = azurerm_storage_account.tfstate.name
}

output "storage_container_name" {
  value = azurerm_storage_container.tfstate.name
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.central.id
}

output "log_analytics_workspace_name" {
  value = azurerm_log_analytics_workspace.central.name
}
