locals {
  name_suffix = "${var.prefix}-${var.environment}"
  common_tags = merge(var.tags, {
    app         = "traduxai"
    environment = var.environment
  })
}

# ── Azure AI Translator ──────────────────────────────────────────────────────
resource "azurerm_cognitive_account" "translator" {
  name                = "cog-translator-${local.name_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  kind                = "TextTranslation"
  sku_name            = var.translator_sku

  custom_subdomain_name = "translator-${local.name_suffix}"
  tags                  = local.common_tags
}

# ── Azure AI Document Intelligence ──────────────────────────────────────────
resource "azurerm_cognitive_account" "docint" {
  name                = "cog-docint-${local.name_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  kind                = "FormRecognizer"
  sku_name            = var.document_intelligence_sku

  custom_subdomain_name = "docint-${local.name_suffix}"
  tags                  = local.common_tags
}

# ── Azure Custom Vision — Training ──────────────────────────────────────────
resource "azurerm_cognitive_account" "vision_training" {
  name                = "cog-vision-train-${local.name_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  kind                = "CustomVision.Training"
  sku_name            = var.custom_vision_sku

  custom_subdomain_name = "vision-train-${local.name_suffix}"
  tags                  = local.common_tags
}

# ── Azure Custom Vision — Prediction ────────────────────────────────────────
resource "azurerm_cognitive_account" "vision_prediction" {
  name                = "cog-vision-pred-${local.name_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  kind                = "CustomVision.Prediction"
  sku_name            = var.custom_vision_sku

  custom_subdomain_name = "vision-pred-${local.name_suffix}"
  tags                  = local.common_tags
}

# ── Azure AI Language ────────────────────────────────────────────────────────
resource "azurerm_cognitive_account" "language" {
  name                = "cog-language-${local.name_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  kind                = "TextAnalytics"
  sku_name            = var.language_sku

  custom_subdomain_name = "language-${local.name_suffix}"
  tags                  = local.common_tags
}

# ── Azure Blob Storage ───────────────────────────────────────────────────────
resource "azurerm_storage_account" "documents" {
  name                     = var.storage_account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }

  tags = local.common_tags
}

resource "azurerm_storage_container" "documents" {
  name                  = "documents"
  storage_account_name  = azurerm_storage_account.documents.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "translated" {
  name                  = "translations"
  storage_account_name  = azurerm_storage_account.documents.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "temp" {
  name                  = "temp"
  storage_account_name  = azurerm_storage_account.documents.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "source_dt" {
  name                  = "source-dt"
  storage_account_name  = azurerm_storage_account.documents.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "target_dt" {
  name                  = "target-dt"
  storage_account_name  = azurerm_storage_account.documents.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "glossaries_dt" {
  name                  = "glossaries-dt"
  storage_account_name  = azurerm_storage_account.documents.name
  container_access_type = "private"
}

# ── Azure Service Bus ────────────────────────────────────────────────────────
resource "azurerm_servicebus_namespace" "main" {
  name                = "sb-${local.name_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  tags                = local.common_tags
}

resource "azurerm_servicebus_queue" "translation_jobs" {
  name         = "translation-jobs"
  namespace_id = azurerm_servicebus_namespace.main.id

  max_delivery_count                   = 3
  dead_lettering_on_message_expiration = true
  default_message_ttl                  = "P7D"
}

resource "azurerm_servicebus_queue" "batch_jobs" {
  name         = "batch-jobs"
  namespace_id = azurerm_servicebus_namespace.main.id

  max_delivery_count  = 3
  default_message_ttl = "P7D"
  requires_session    = false
}

resource "azurerm_servicebus_topic" "notifications" {
  name         = "notifications"
  namespace_id = azurerm_servicebus_namespace.main.id

  default_message_ttl = "P1D"
}

resource "azurerm_servicebus_subscription" "webhooks" {
  name               = "webhooks"
  topic_id           = azurerm_servicebus_topic.notifications.id
  max_delivery_count = 5
}

resource "azurerm_servicebus_subscription" "email" {
  name               = "email"
  topic_id           = azurerm_servicebus_topic.notifications.id
  max_delivery_count = 3
}

# ── Azure AI Search (Translation Memory) ────────────────────────────────────
resource "azurerm_search_service" "tm" {
  count               = var.enable_search ? 1 : 0
  name                = "search-${local.name_suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.search_sku
  tags                = local.common_tags
}

# ── Key Vault Secrets ────────────────────────────────────────────────────────
resource "azurerm_key_vault_secret" "translator_key" {
  name         = "traduxai-translator-key"
  value        = azurerm_cognitive_account.translator.primary_access_key
  key_vault_id = var.keyvault_id
}

resource "azurerm_key_vault_secret" "translator_endpoint" {
  name         = "traduxai-translator-endpoint"
  value        = azurerm_cognitive_account.translator.endpoint
  key_vault_id = var.keyvault_id
}

resource "azurerm_key_vault_secret" "docint_key" {
  name         = "traduxai-docint-key"
  value        = azurerm_cognitive_account.docint.primary_access_key
  key_vault_id = var.keyvault_id
}

resource "azurerm_key_vault_secret" "docint_endpoint" {
  name         = "traduxai-docint-endpoint"
  value        = azurerm_cognitive_account.docint.endpoint
  key_vault_id = var.keyvault_id
}

resource "azurerm_key_vault_secret" "vision_prediction_key" {
  name         = "traduxai-vision-pred-key"
  value        = azurerm_cognitive_account.vision_prediction.primary_access_key
  key_vault_id = var.keyvault_id
}

resource "azurerm_key_vault_secret" "vision_prediction_endpoint" {
  name         = "traduxai-vision-pred-endpoint"
  value        = azurerm_cognitive_account.vision_prediction.endpoint
  key_vault_id = var.keyvault_id
}

resource "azurerm_key_vault_secret" "language_key" {
  name         = "traduxai-language-key"
  value        = azurerm_cognitive_account.language.primary_access_key
  key_vault_id = var.keyvault_id
}

resource "azurerm_key_vault_secret" "language_endpoint" {
  name         = "traduxai-language-endpoint"
  value        = azurerm_cognitive_account.language.endpoint
  key_vault_id = var.keyvault_id
}

resource "azurerm_key_vault_secret" "servicebus_connection" {
  name         = "traduxai-servicebus-connection"
  value        = azurerm_servicebus_namespace.main.default_primary_connection_string
  key_vault_id = var.keyvault_id
}

resource "azurerm_key_vault_secret" "search_key" {
  name         = "traduxai-search-key"
  value        = var.enable_search ? azurerm_search_service.tm[0].primary_key : "disabled"
  key_vault_id = var.keyvault_id
}

resource "azurerm_key_vault_secret" "search_endpoint" {
  name         = "traduxai-search-endpoint"
  value        = var.enable_search ? "https://${azurerm_search_service.tm[0].name}.search.windows.net" : "disabled"
  key_vault_id = var.keyvault_id
}

resource "azurerm_key_vault_secret" "storage_connection" {
  name         = "traduxai-storage-connection"
  value        = azurerm_storage_account.documents.primary_connection_string
  key_vault_id = var.keyvault_id
}
