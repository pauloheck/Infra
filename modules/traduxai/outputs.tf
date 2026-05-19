output "translator_endpoint" {
  value = azurerm_cognitive_account.translator.endpoint
}

output "docint_endpoint" {
  value = azurerm_cognitive_account.docint.endpoint
}

output "vision_prediction_endpoint" {
  value = azurerm_cognitive_account.vision_prediction.endpoint
}

output "vision_training_endpoint" {
  value = azurerm_cognitive_account.vision_training.endpoint
}

output "language_endpoint" {
  value = azurerm_cognitive_account.language.endpoint
}

output "storage_account_url" {
  value = azurerm_storage_account.documents.primary_blob_endpoint
}

output "servicebus_namespace" {
  value = azurerm_servicebus_namespace.main.name
}

output "servicebus_translation_queue" {
  value = azurerm_servicebus_queue.translation_jobs.name
}

output "servicebus_batch_queue" {
  value = azurerm_servicebus_queue.batch_jobs.name
}

output "search_endpoint" {
  value = var.enable_search ? "https://${azurerm_search_service.tm[0].name}.search.windows.net" : ""
}

output "storage_account_name" {
  value = azurerm_storage_account.documents.name
}

output "vision_project_id" {
  description = "A ser preenchido manualmente após criar o projeto no Custom Vision portal"
  value       = "PENDING — criar projeto em https://customvision.ai"
}

output "document_translator_endpoint" {
  value = "https://translator-${local.name_suffix}.cognitiveservices.azure.com/"
}
