###############################################################################
# Module: acr
# Azure Container Registry
###############################################################################

variable "project" { type = string }
variable "env" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "tags" { type = map(string) }

variable "sku" {
  type    = string
  default = "Standard"
}

variable "log_analytics_workspace_id" {
  type    = string
  default = ""
}

variable "enable_diagnostics" {
  type    = bool
  default = true
}

variable "name_override" {
  type        = string
  default     = ""
  description = "Nome customizado para o ACR (substitui acr{project}{env}). Útil quando o nome padrão já está em uso globalmente."
}

# ---------- ACR ---------------------------------------------------------------
locals {
  acr_name = var.name_override != "" ? var.name_override : "acr${var.project}${var.env}"
}

resource "azurerm_container_registry" "main" {
  name                = local.acr_name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku
  admin_enabled       = false
  tags                = var.tags
}

# ---------- Diagnostic Settings -----------------------------------------------
resource "azurerm_monitor_diagnostic_setting" "acr" {
  count = var.enable_diagnostics ? 1 : 0

  name                       = "diag-acr-${var.project}-${var.env}"
  target_resource_id         = azurerm_container_registry.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "ContainerRegistryRepositoryEvents"
  }

  enabled_log {
    category = "ContainerRegistryLoginEvents"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# ---------- Outputs -----------------------------------------------------------
output "acr_id" {
  value = azurerm_container_registry.main.id
}

output "acr_name" {
  value = azurerm_container_registry.main.name
}

output "acr_login_server" {
  value = azurerm_container_registry.main.login_server
}
