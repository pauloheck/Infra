output "resource_group_name" {
  description = "Nome do Resource Group"
  value       = azurerm_resource_group.core.name
}

output "container_app_url" {
  description = "FQDN da Container App"
  value       = azurerm_container_app.core.ingress[0].fqdn
}

output "acr_login_server" {
  description = "Login server do ACR"
  value       = azurerm_container_registry.core.login_server
}

output "acr_name" {
  description = "Nome do ACR"
  value       = azurerm_container_registry.core.name
}

output "log_analytics_workspace_id" {
  description = "ID do Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.core.id
}

output "app_insights_connection_string" {
  description = "Connection string do Application Insights"
  value       = azurerm_application_insights.core.connection_string
  sensitive   = true
}

output "managed_identity_id" {
  description = "ID da Managed Identity"
  value       = azurerm_user_assigned_identity.core.id
}

output "managed_identity_client_id" {
  description = "Client ID da Managed Identity"
  value       = azurerm_user_assigned_identity.core.client_id
}
