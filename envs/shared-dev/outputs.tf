###############################################################################
# Shared Dev — Outputs
###############################################################################

output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "aks_name" {
  value = module.aks.aks_name
}

output "aks_fqdn" {
  value = module.aks.aks_fqdn
}

output "acr_login_server" {
  value = module.acr.acr_login_server
}

output "acr_name" {
  value = module.acr.acr_name
}

output "postgres_fqdn" {
  value = module.postgres.server_fqdn
}

output "kv_beeai_name" {
  value = module.kv_beeai.key_vault_name
}

output "kv_bovipro_name" {
  value = module.kv_bovipro.key_vault_name
}

output "openai_beeai_endpoint" {
  value = module.ai.openai_endpoint
}

output "kv_iai_name" {
  value = module.kv_iai.key_vault_name
}

output "openai_iai_endpoint" {
  value = azurerm_cognitive_account.openai_iai.endpoint
}

output "log_analytics_workspace_id" {
  value = module.observability.log_analytics_workspace_id
}

output "app_insights_connection_string" {
  value     = module.observability.app_insights_connection_string
  sensitive = true
}

output "bovipro_dev_public_ip" {
  value       = azurerm_public_ip.bovipro_dev.ip_address
  description = "IP público estático BoviPro DEV — DNS: dev.bovipro.com.br"
}

output "bovipro_prod_public_ip" {
  value       = azurerm_public_ip.bovipro_prod.ip_address
  description = "IP público estático BoviPro PROD — DNS: bovipro.com.br"
}

output "kv_getchat_name" {
  value       = module.kv_getchat.key_vault_name
  description = "Nome do Key Vault GetChat."
}

output "kv_keycloak_name" {
  value       = module.kv_keycloak.key_vault_name
  description = "Nome do Key Vault Keycloak compartilhado."
}

output "getchat_search_endpoint" {
  value       = "https://${azurerm_search_service.getchat.name}.search.windows.net"
  description = "Endpoint do Azure AI Search (GetChat RAG)."
}

output "getchat_oai_endpoint" {
  value       = azurerm_cognitive_account.openai_getchat.endpoint
  description = "Endpoint Azure OpenAI (GetChat embeddings)."
}

output "kv_traduxai_name" {
  value       = module.kv_traduxai.key_vault_name
  description = "Nome do Key Vault Tradux AI."
}

output "traduxai_translator_endpoint" {
  value       = module.traduxai.translator_endpoint
  description = "Endpoint Azure AI Translator."
}

output "traduxai_docint_endpoint" {
  value       = module.traduxai.docint_endpoint
  description = "Endpoint Azure Document Intelligence."
}

output "traduxai_language_endpoint" {
  value       = module.traduxai.language_endpoint
  description = "Endpoint Azure AI Language."
}

output "traduxai_storage_url" {
  value       = module.traduxai.storage_account_url
  description = "URL da Storage Account Tradux AI."
}

output "traduxai_search_endpoint" {
  value       = module.traduxai.search_endpoint
  description = "Endpoint Azure AI Search (Translation Memory)."
}

output "traduxai_servicebus_namespace" {
  value       = module.traduxai.servicebus_namespace
  description = "Namespace do Azure Service Bus Tradux AI."
}

output "traduxai_storage_account_name" {
  value       = module.traduxai.storage_account_name
  description = "Storage Account Tradux AI."
}

# ─── Instruções pós-apply ────────────────────────────────────────────────────
#
# 1. Criar secrets manuais nos Key Vaults:
#    az keyvault secret set --vault-name kv-beeai-shareddev \
#      --name jwt-secret-key --value "$(openssl rand -base64 48)"
#
#    az keyvault secret set --vault-name kv-bovipro-dev \
#      --name bovipro-jwt-secret --value "$(openssl rand -base64 48)"
#
#    az keyvault secret set --vault-name kv-getchat-dev \
#      --name jwt-secret-key --value "$(openssl rand -base64 48)"
#
# 2. Atualizar GitHub Secrets nos três repos:
#
#    BeeAI (repo beeai):
#      ACR_NAME           = acrshareddev
#      AKS_NAME           = aks-shared-dev
#      AKS_RESOURCE_GROUP = rg-shared-dev
#
#    BoviPro (repo bovipro-infra):
#      ACR_NAME           = acrshareddev
#      AKS_NAME           = aks-shared-dev
#      AKS_RESOURCE_GROUP = rg-shared-dev
#
#    IAI (repo IAI):
#      ACR_NAME           = acrheckiodev
#      AKS_NAME           = aks-shared-dev
#      AKS_RESOURCE_GROUP = rg-shared-dev
#      AZURE_CLIENT_ID    = <client-id-do-oidc>
#      AZURE_TENANT_ID    = <tenant-id>
#      AZURE_SUBSCRIPTION_ID = <subscription-id>
#
# 3. Garantir que o SP do GitHub Actions tem as roles no AKS compartilhado:
#    az role assignment create \
#      --assignee <client-id> \
#      --role "Azure Kubernetes Service Cluster Admin Role" \
#      --scope $(az aks show -g rg-shared-dev -n aks-shared-dev --query id -o tsv)
