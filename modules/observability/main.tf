###############################################################################
# Module: observability
# Log Analytics + Application Insights + Diagnostic Settings helpers
###############################################################################

variable "project" { type = string }
variable "env" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "tags" { type = map(string) }

variable "retention_in_days" {
  type    = number
  default = 30
}

variable "enable_container_insights" {
  type    = bool
  default = true
}

variable "action_group_short_name" {
  type        = string
  default     = "beeai-crit"
  description = "Short name do Action Group (máx 12 chars)."
}

# ---------- Log Analytics Workspace -------------------------------------------
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${var.project}-${var.env}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.retention_in_days
  tags                = var.tags
}

# ---------- Log Analytics Solution (Container Insights) -----------------------
resource "azurerm_log_analytics_solution" "containers" {
  count = var.enable_container_insights ? 1 : 0

  solution_name         = "ContainerInsights"
  location              = var.location
  resource_group_name   = var.resource_group_name
  workspace_resource_id = azurerm_log_analytics_workspace.main.id
  workspace_name        = azurerm_log_analytics_workspace.main.name

  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/ContainerInsights"
  }

  tags = var.tags
}

# ---------- Application Insights (workspace-based) ----------------------------
resource "azurerm_application_insights" "main" {
  name                = "appi-${var.project}-${var.env}"
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  tags                = var.tags
}

# ---------- Action Group (alertas básicos) ------------------------------------
resource "azurerm_monitor_action_group" "critical" {
  name                = "ag-${var.project}-${var.env}-critical"
  resource_group_name = var.resource_group_name
  short_name          = var.action_group_short_name
  tags                = var.tags

  # Adicionar e-mail ou webhook conforme necessário
  # email_receiver {
  #   name          = "ops-team"
  #   email_address = "ops@beeai.com"
  # }
}

# ---------- Outputs -----------------------------------------------------------
output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_name" {
  value = azurerm_log_analytics_workspace.main.name
}

output "app_insights_id" {
  value = azurerm_application_insights.main.id
}

output "app_insights_instrumentation_key" {
  value     = azurerm_application_insights.main.instrumentation_key
  sensitive = true
}

output "app_insights_connection_string" {
  value     = azurerm_application_insights.main.connection_string
  sensitive = true
}

output "action_group_id" {
  value = azurerm_monitor_action_group.critical.id
}
