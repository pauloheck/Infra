###############################################################################
# Module: postgres
# Azure Database for PostgreSQL Flexible Server
###############################################################################

variable "project" { type = string }
variable "env" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "tags" { type = map(string) }

variable "administrator_login" {
  type    = string
  default = "beeaiadmin"
}

variable "administrator_password" {
  type      = string
  sensitive = true
}

variable "sku_name" {
  type    = string
  default = "B_Standard_B1ms"
}

variable "storage_mb" {
  type    = number
  default = 32768
}

variable "pg_version" {
  type    = string
  default = "16"
}

variable "delegated_subnet_id" {
  type    = string
  default = ""
}

variable "vnet_id" {
  type    = string
  default = ""
}

variable "log_analytics_workspace_id" {
  type    = string
  default = ""
}

variable "enable_vnet_integration" {
  type    = bool
  default = true
}

variable "enable_diagnostics" {
  type    = bool
  default = true
}

variable "high_availability" {
  type    = bool
  default = false
}

variable "backup_retention_days" {
  type    = number
  default = 7
}

variable "geo_redundant_backup" {
  type    = bool
  default = false
}

variable "server_name_override" {
  type        = string
  default     = ""
  description = "Nome customizado para o servidor PostgreSQL (substitui psql-{project}-{env}). Útil quando o nome padrão já está em uso globalmente."
}

# ---------- Private DNS Zone (para VNet integration) --------------------------
resource "azurerm_private_dns_zone" "postgres" {
  count = var.enable_vnet_integration ? 1 : 0

  name                = "${var.project}-${var.env}.postgres.database.azure.com"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  count = var.enable_vnet_integration ? 1 : 0

  name                  = "vnetlink-pg-${var.env}"
  private_dns_zone_name = azurerm_private_dns_zone.postgres[0].name
  resource_group_name   = var.resource_group_name
  virtual_network_id    = var.vnet_id
}

# ---------- PostgreSQL Flexible Server ----------------------------------------
locals {
  pg_server_name = var.server_name_override != "" ? var.server_name_override : "psql-${var.project}-${var.env}"
}

resource "azurerm_postgresql_flexible_server" "main" {
  name                   = local.pg_server_name
  resource_group_name    = var.resource_group_name
  location               = var.location
  version                = var.pg_version
  administrator_login    = var.administrator_login
  administrator_password = var.administrator_password
  sku_name               = var.sku_name
  storage_mb             = var.storage_mb
  zone                   = "1"
  tags                   = var.tags

  backup_retention_days        = var.backup_retention_days
  geo_redundant_backup_enabled = var.geo_redundant_backup

  dynamic "high_availability" {
    for_each = var.high_availability ? [1] : []
    content {
      mode                      = "ZoneRedundant"
      standby_availability_zone = "2"
    }
  }

  # VNet integration (quando delegated_subnet_id é fornecido)
  delegated_subnet_id           = var.enable_vnet_integration ? var.delegated_subnet_id : null
  private_dns_zone_id           = var.enable_vnet_integration ? azurerm_private_dns_zone.postgres[0].id : null
  public_network_access_enabled = var.enable_vnet_integration ? false : true

  lifecycle {
    # prevent_destroy = true  # Descomente para PRD
    ignore_changes = [
      administrator_password,
    ]
  }
}

# ---------- Default database --------------------------------------------------
resource "azurerm_postgresql_flexible_server_database" "beeai" {
  name      = "beeai"
  server_id = azurerm_postgresql_flexible_server.main.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# ---------- Diagnostic Settings -----------------------------------------------
resource "azurerm_monitor_diagnostic_setting" "postgres" {
  count = var.enable_diagnostics ? 1 : 0

  name                       = "diag-pg-${var.project}-${var.env}"
  target_resource_id         = azurerm_postgresql_flexible_server.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "PostgreSQLLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# ---------- Outputs -----------------------------------------------------------
output "server_id" {
  value = azurerm_postgresql_flexible_server.main.id
}

output "server_name" {
  value = azurerm_postgresql_flexible_server.main.name
}

output "server_fqdn" {
  value = azurerm_postgresql_flexible_server.main.fqdn
}

output "database_name" {
  value = azurerm_postgresql_flexible_server_database.beeai.name
}
