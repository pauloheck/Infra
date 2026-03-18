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

output "openai_endpoint" {
  value = module.ai.openai_endpoint
}

output "log_analytics_workspace_id" {
  value = module.observability.log_analytics_workspace_id
}

output "app_insights_connection_string" {
  value     = module.observability.app_insights_connection_string
  sensitive = true
}

# ─── Instruções pós-apply ────────────────────────────────────────────────────
#
# 1. Criar secrets manuais nos Key Vaults:
#    az keyvault secret set --vault-name kv-beeai-dev \
#      --name jwt-secret-key --value "<jwt-secret>"
#
#    az keyvault secret set --vault-name kv-bovipro-dev \
#      --name bovipro-jwt-secret --value "<jwt-secret>"
#
# 2. Atualizar GitHub Secrets nos dois repos:
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
#      AZURE_CLIENT_ID    = <client-id-do-oidc>
#      AZURE_TENANT_ID    = <tenant-id>
#      AZURE_SUBSCRIPTION_ID = <subscription-id>
#
# 3. Garantir que o SP do GitHub Actions tem as roles no AKS compartilhado:
#    az role assignment create \
#      --assignee <client-id> \
#      --role "Azure Kubernetes Service Cluster Admin Role" \
#      --scope $(az aks show -g rg-shared-dev -n aks-shared-dev --query id -o tsv)
