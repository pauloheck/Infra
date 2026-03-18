###############################################################################
# Outputs – Dev
###############################################################################

output "container_app_url" {
  description = "URL da Container App"
  value       = module.core.container_app_url
}

output "acr_login_server" {
  description = "Login server do ACR"
  value       = module.core.acr_login_server
}

output "openai_endpoint" {
  description = "Endpoint do Azure OpenAI"
  value       = module.openai.openai_endpoint
}

output "app_insights_connection_string" {
  description = "Connection string do App Insights"
  value       = module.core.app_insights_connection_string
  sensitive   = true
}
