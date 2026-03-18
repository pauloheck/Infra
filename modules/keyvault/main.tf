###############################################################################
# Module: keyvault
# Azure Key Vault com RBAC + Diagnostic Settings
###############################################################################

variable "project" { type = string }
variable "env" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "tags" { type = map(string) }
variable "tenant_id" { type = string }

variable "log_analytics_workspace_id" {
  type    = string
  default = ""
}

variable "enable_diagnostics" {
  type    = bool
  default = true
}

variable "purge_protection_enabled" {
  type    = bool
  default = false
}

variable "soft_delete_retention_days" {
  type    = number
  default = 7
}

variable "name_override" {
  type        = string
  default     = ""
  description = "Nome customizado para o Key Vault (substitui kv-{project}-{env}). Útil quando o nome padrão já está em uso globalmente."
}

# ---------- Key Vault ---------------------------------------------------------
locals {
  kv_name = var.name_override != "" ? var.name_override : "kv-${var.project}-${var.env}"
}

resource "azurerm_key_vault" "main" {
  name                       = local.kv_name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = var.tenant_id
  sku_name                   = "standard"
  purge_protection_enabled   = var.purge_protection_enabled
  soft_delete_retention_days = var.soft_delete_retention_days

  enable_rbac_authorization = true

  tags = var.tags
}

# ---------- Diagnostic Settings -----------------------------------------------
resource "azurerm_monitor_diagnostic_setting" "keyvault" {
  count = var.enable_diagnostics ? 1 : 0

  name                       = "diag-kv-${var.project}-${var.env}"
  target_resource_id         = azurerm_key_vault.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_log {
    category = "AzurePolicyEvaluationDetails"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# ---------- Outputs -----------------------------------------------------------
output "key_vault_id" {
  value = azurerm_key_vault.main.id
}

output "key_vault_name" {
  value = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  value = azurerm_key_vault.main.vault_uri
}
