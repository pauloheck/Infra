###############################################################################
# Module: AI – Outputs
###############################################################################

output "openai_endpoint" {
  value       = azurerm_cognitive_account.openai.endpoint
  description = "Azure OpenAI endpoint URL (used as AI_FOUNDRY_ENDPOINT)."
}

output "openai_id" {
  value = azurerm_cognitive_account.openai.id
}

output "content_safety_endpoint" {
  value       = azurerm_cognitive_account.content_safety.endpoint
  description = "Azure Content Safety endpoint URL."
}

output "content_safety_id" {
  value = azurerm_cognitive_account.content_safety.id
}

output "gpt4o_deployment_name" {
  value = azurerm_cognitive_deployment.gpt4o.name
}

output "gpt4o_mini_deployment_name" {
  value = azurerm_cognitive_deployment.gpt4o_mini.name
}
