###############################################################################
# Shared Dev — Infra mínima compartilhada para todas as aplicações _heck
#
# Recursos criados:
#   rg-shared-dev          Resource Group único
#   vnet-shared-dev        VNet + subnets (AKS, data, PE, appgw)
#   aks-shared-dev         AKS 1 nó Standard_D2s_v3 (sem user pool)
#   acrheckiodev           ACR Basic compartilhado
#   psql-heckio-dev        PostgreSQL B1ms — databases: beeai, bovipro, iai
#   kv-beeai-shareddev     Key Vault BeeAI
#   kv-bovipro-dev         Key Vault BoviPro
#   kv-iai-shareddev       Key Vault IAI
#   kv-getchat-dev         Key Vault GetChat
#   oai-iai-dev            Azure OpenAI (IAI only)
#   oai-getchat-dev        Azure OpenAI (GetChat embeddings)
#   search-getchat-dev     Azure AI Search (GetChat RAG)
#   law-shared-dev         Log Analytics (30 dias)
#   appi-shared-dev        Application Insights
#   oai-beeai-shareddev    Azure OpenAI (BeeAI only)
#   cs-beeai-shareddev     Content Safety (BeeAI only)
#
# Para adicionar uma nova aplicação: ver seção "Adicionando nova app" ao final.
# Custo estimado: ~$97/mês (vs ~$268/mês com infras separadas)
###############################################################################

data "azurerm_client_config" "current" {}

# ---------- Resource Group ----------------------------------------------------
resource "azurerm_resource_group" "main" {
  name     = "rg-${var.project}-${var.env}"
  location = var.location
  tags     = var.tags
}

# ---------- Network -----------------------------------------------------------
module "network" {
  source = "../../modules/network"

  project             = var.project
  env                 = var.env
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  vnet_address_space  = var.vnet_address_space
  subnet_aks_prefix   = var.subnet_aks_prefix
  subnet_data_prefix  = var.subnet_data_prefix
  subnet_pe_prefix    = var.subnet_pe_prefix
  subnet_appgw_prefix = var.subnet_appgw_prefix
}

# ---------- Observability (compartilhado) ------------------------------------
module "observability" {
  source = "../../modules/observability"

  project             = var.project
  env                 = var.env
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  retention_in_days         = var.log_retention_days
  enable_container_insights = false
  action_group_short_name   = "shared-crit"
}

# ---------- ACR (compartilhado — todas as apps usam) -------------------------
module "acr" {
  source = "../../modules/acr"

  project             = var.project
  env                 = var.env
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
  sku                 = "Basic"
  enable_diagnostics  = false
  name_override       = "acrheckiodev"
}

# ---------- AKS (único cluster compartilhado, sem user pool) -----------------
module "aks" {
  source = "../../modules/aks"

  project             = var.project
  env                 = var.env
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  kubernetes_version = var.kubernetes_version
  subnet_id          = module.network.subnet_aks_id

  system_node_count = var.system_node_count
  system_vm_size    = var.system_vm_size
  enable_user_pool  = false

  acr_id                     = module.acr.acr_id
  log_analytics_workspace_id = module.observability.log_analytics_workspace_id
  enable_diagnostics         = false

  depends_on = [module.network]
}

# ---------- Static Public IPs (BoviPro) — IPs fixos para DNS bovipro.com.br ----
resource "azurerm_public_ip" "bovipro_dev" {
  name                = "pip-bovipro-dev"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_public_ip" "bovipro_prod" {
  name                = "pip-bovipro-prod"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# ---------- PostgreSQL (compartilhado — servidor único, databases separados) --
module "postgres" {
  source = "../../modules/postgres"

  project             = var.project
  env                 = var.env
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  administrator_login    = "pgadmin"
  administrator_password = var.pg_admin_password
  sku_name               = var.pg_sku
  storage_mb             = var.pg_storage_mb

  delegated_subnet_id = module.network.subnet_data_id
  vnet_id             = module.network.vnet_id

  enable_diagnostics    = false
  high_availability     = false
  backup_retention_days = 7
  geo_redundant_backup  = false
  server_name_override  = "psql-heckio-dev"

  depends_on = [module.network]
}

# ---------- Databases por aplicação -------------------------------------------
# O database "beeai" é criado pelo próprio módulo postgres (default).

resource "azurerm_postgresql_flexible_server_database" "bovipro" {
  name      = "bovipro"
  server_id = module.postgres.server_id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# Extensões necessárias (UUID-OSSP para BoviPro, disponível para todas)
resource "azurerm_postgresql_flexible_server_configuration" "extensions" {
  name      = "azure.extensions"
  server_id = module.postgres.server_id
  value     = "UUID-OSSP,PGCRYPTO"

  depends_on = [module.postgres]
}

###############################################################################
# KEY VAULTS POR APLICAÇÃO
# Cada app tem seu próprio KV — isolamento total de secrets.
# Para nova app: duplicar bloco kv_ + role_assignments abaixo.
###############################################################################

# ---------- Key Vault — BeeAI -------------------------------------------------
module "kv_beeai" {
  source = "../../modules/keyvault"

  project             = "beeai"
  env                 = var.env
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
  tenant_id           = data.azurerm_client_config.current.tenant_id
  enable_diagnostics  = false
  name_override       = "kv-beeai-shareddev"

  depends_on = [module.aks]
}

# ---------- Key Vault — BoviPro -----------------------------------------------
module "kv_bovipro" {
  source = "../../modules/keyvault"

  project             = "bovipro"
  env                 = var.env
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
  tenant_id           = data.azurerm_client_config.current.tenant_id
  enable_diagnostics  = false

  depends_on = [module.aks]
}

# ---------- RBAC: AKS identity → Secrets Officer (todos os KVs) --------------
resource "azurerm_role_assignment" "aks_kv_beeai" {
  scope                            = module.kv_beeai.key_vault_id
  role_definition_name             = "Key Vault Secrets Officer"
  principal_id                     = module.aks.aks_identity_principal_id
  skip_service_principal_aad_check = true
  depends_on                       = [module.kv_beeai, module.aks]
}

resource "azurerm_role_assignment" "aks_kv_bovipro" {
  scope                            = module.kv_bovipro.key_vault_id
  role_definition_name             = "Key Vault Secrets Officer"
  principal_id                     = module.aks.aks_identity_principal_id
  skip_service_principal_aad_check = true
  depends_on                       = [module.kv_bovipro, module.aks]
}

# ---------- RBAC: Terraform (CI/CD) → Secrets Officer (todos os KVs) ---------
resource "azurerm_role_assignment" "terraform_kv_beeai" {
  scope                = module.kv_beeai.key_vault_id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [module.kv_beeai]
  lifecycle { ignore_changes = [principal_id] }
}

resource "azurerm_role_assignment" "terraform_kv_bovipro" {
  scope                = module.kv_bovipro.key_vault_id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [module.kv_bovipro]
  lifecycle { ignore_changes = [principal_id] }
}

###############################################################################
# SECRETS POR APLICAÇÃO nos Key Vaults
###############################################################################

# --- BeeAI ---
resource "azurerm_key_vault_secret" "beeai_pg_connection" {
  name         = "pg-connection-string"
  value        = "postgresql://pgadmin:${var.pg_admin_password}@${module.postgres.server_fqdn}:5432/beeai?sslmode=require"
  key_vault_id = module.kv_beeai.key_vault_id
  depends_on   = [module.kv_beeai, module.postgres, azurerm_role_assignment.terraform_kv_beeai]
}

resource "azurerm_key_vault_secret" "beeai_appinsights" {
  name         = "appinsights-connection-string"
  value        = module.observability.app_insights_connection_string
  key_vault_id = module.kv_beeai.key_vault_id
  depends_on   = [module.kv_beeai, azurerm_role_assignment.terraform_kv_beeai]
}

# --- BoviPro ---
resource "azurerm_key_vault_secret" "bovipro_pg_connection" {
  name         = "bovipro-pg-connection"
  value        = "postgresql://pgadmin:${var.pg_admin_password}@${module.postgres.server_fqdn}:5432/bovipro?sslmode=require"
  key_vault_id = module.kv_bovipro.key_vault_id
  depends_on   = [module.kv_bovipro, module.postgres, azurerm_role_assignment.terraform_kv_bovipro]
}

# Nota: secrets JWT são criados manualmente após o apply:
#   az keyvault secret set --vault-name kv-beeai-shareddev --name jwt-secret-key --value "$(openssl rand -base64 48)"
#   az keyvault secret set --vault-name kv-bovipro-dev     --name bovipro-jwt-secret --value "$(openssl rand -base64 48)"

###############################################################################
# SERVIÇOS ESPECÍFICOS POR APLICAÇÃO
# Recursos que só uma app usa ficam identificados claramente aqui.
###############################################################################

# ---------- Azure OpenAI + Content Safety (BeeAI only) -----------------------
module "ai" {
  source = "../../modules/ai"

  project             = "beeai"
  env                 = var.env
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  aks_identity_principal_id  = module.aks.aks_identity_principal_id
  kubelet_identity_object_id = module.aks.kubelet_identity_object_id
  key_vault_id               = module.kv_beeai.key_vault_id

  gpt4o_capacity      = var.ai_gpt4o_capacity
  gpt4o_mini_capacity = var.ai_gpt4o_mini_capacity

  openai_name_override         = "oai-beeai-shareddev"
  content_safety_name_override = "cs-beeai-shareddev"

  depends_on = [module.aks, module.kv_beeai]
}

resource "azurerm_key_vault_secret" "ai_foundry_endpoint" {
  name         = "ai-foundry-endpoint"
  value        = module.ai.openai_endpoint
  key_vault_id = module.kv_beeai.key_vault_id
  depends_on   = [module.kv_beeai, module.ai, azurerm_role_assignment.terraform_kv_beeai]
}

resource "azurerm_key_vault_secret" "content_safety_endpoint" {
  name         = "content-safety-endpoint"
  value        = module.ai.content_safety_endpoint
  key_vault_id = module.kv_beeai.key_vault_id
  depends_on   = [module.kv_beeai, module.ai, azurerm_role_assignment.terraform_kv_beeai]
}

resource "azurerm_key_vault_secret" "ai_deployment_dev" {
  name         = "ai-foundry-deployment-dev"
  value        = module.ai.gpt4o_mini_deployment_name
  key_vault_id = module.kv_beeai.key_vault_id
  depends_on   = [module.kv_beeai, module.ai, azurerm_role_assignment.terraform_kv_beeai]
}

resource "azurerm_key_vault_secret" "ai_deployment_prod" {
  name         = "ai-foundry-deployment-prod"
  value        = module.ai.gpt4o_deployment_name
  key_vault_id = module.kv_beeai.key_vault_id
  depends_on   = [module.kv_beeai, module.ai, azurerm_role_assignment.terraform_kv_beeai]
}

###############################################################################
# SERVIÇOS ESPECÍFICOS — IAI
# Recursos migrados do antigo envs/iai-dev (Container Apps) para AKS compartilhado.
###############################################################################

# ---------- Database IAI -------------------------------------------------------
resource "azurerm_postgresql_flexible_server_database" "iai" {
  name      = "iai"
  server_id = module.postgres.server_id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# ---------- Key Vault — IAI ----------------------------------------------------
module "kv_iai" {
  source = "../../modules/keyvault"

  project             = "iai"
  env                 = var.env
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
  tenant_id           = data.azurerm_client_config.current.tenant_id
  enable_diagnostics  = false
  name_override       = "kv-iai-shareddev"

  depends_on = [module.aks]
}

# ---------- RBAC: AKS identity → Secrets Officer (KV IAI) ---------------------
resource "azurerm_role_assignment" "aks_kv_iai" {
  scope                            = module.kv_iai.key_vault_id
  role_definition_name             = "Key Vault Secrets Officer"
  principal_id                     = module.aks.aks_identity_principal_id
  skip_service_principal_aad_check = true
  depends_on                       = [module.kv_iai, module.aks]
}

# ---------- RBAC: Terraform (CI/CD) → Secrets Officer (KV IAI) ----------------
resource "azurerm_role_assignment" "terraform_kv_iai" {
  scope                = module.kv_iai.key_vault_id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [module.kv_iai]
  lifecycle { ignore_changes = [principal_id] }
}

# ---------- Azure OpenAI (IAI only) -------------------------------------------
resource "azurerm_cognitive_account" "openai_iai" {
  name                  = "oai-iai-${var.env}"
  resource_group_name   = azurerm_resource_group.main.name
  location              = var.location
  kind                  = "OpenAI"
  sku_name              = "S0"
  custom_subdomain_name = "oai-iai-${var.env}"

  identity {
    type = "SystemAssigned"
  }

  network_acls {
    default_action = "Allow"
  }

  tags = var.tags
}

resource "azurerm_cognitive_deployment" "iai_gpt4o_mini" {
  name                 = "gpt-4o-mini"
  cognitive_account_id = azurerm_cognitive_account.openai_iai.id

  model {
    format  = "OpenAI"
    name    = "gpt-4o"
    version = "2024-11-20"
  }

  scale {
    type     = "Standard"
    capacity = 1
  }
}

# ---------- Secrets IAI no Key Vault -------------------------------------------
resource "azurerm_key_vault_secret" "iai_pg_connection" {
  name         = "pg-connection-string"
  value        = "postgresql://pgadmin:${var.pg_admin_password}@${module.postgres.server_fqdn}:5432/iai?sslmode=require"
  key_vault_id = module.kv_iai.key_vault_id
  depends_on   = [module.kv_iai, module.postgres, azurerm_role_assignment.terraform_kv_iai]
}

resource "azurerm_key_vault_secret" "iai_appinsights" {
  name         = "appinsights-connection-string"
  value        = module.observability.app_insights_connection_string
  key_vault_id = module.kv_iai.key_vault_id
  depends_on   = [module.kv_iai, azurerm_role_assignment.terraform_kv_iai]
}

resource "azurerm_key_vault_secret" "iai_openai_endpoint" {
  name         = "azure-openai-endpoint"
  value        = azurerm_cognitive_account.openai_iai.endpoint
  key_vault_id = module.kv_iai.key_vault_id
  depends_on   = [module.kv_iai, azurerm_cognitive_account.openai_iai, azurerm_role_assignment.terraform_kv_iai]
}

resource "azurerm_key_vault_secret" "iai_openai_key" {
  name         = "azure-openai-api-key"
  value        = azurerm_cognitive_account.openai_iai.primary_access_key
  key_vault_id = module.kv_iai.key_vault_id
  depends_on   = [module.kv_iai, azurerm_cognitive_account.openai_iai, azurerm_role_assignment.terraform_kv_iai]
}

resource "azurerm_key_vault_secret" "iai_device_token" {
  name         = "device-token"
  value        = var.iai_device_token
  key_vault_id = module.kv_iai.key_vault_id
  depends_on   = [module.kv_iai, azurerm_role_assignment.terraform_kv_iai]
}

###############################################################################
# PRODUÇÃO — Databases, Key Vaults e Secrets
# Mesma infra (AKS, ACR, PostgreSQL server), namespaces separados.
###############################################################################

# ---------- Databases Prod -----------------------------------------------------
resource "azurerm_postgresql_flexible_server_database" "beeai_prod" {
  name      = "beeai-prod"
  server_id = module.postgres.server_id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

resource "azurerm_postgresql_flexible_server_database" "bovipro_prod" {
  name      = "bovipro-prod"
  server_id = module.postgres.server_id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

resource "azurerm_postgresql_flexible_server_database" "iai_prod" {
  name      = "iai-prod"
  server_id = module.postgres.server_id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# ---------- Key Vaults Prod ----------------------------------------------------
module "kv_beeai_prod" {
  source = "../../modules/keyvault"

  project             = "beeai"
  env                 = "prod"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
  tenant_id           = data.azurerm_client_config.current.tenant_id
  enable_diagnostics  = false
  name_override       = "kv-beeai-prod"

  depends_on = [module.aks]
}

module "kv_bovipro_prod" {
  source = "../../modules/keyvault"

  project             = "bovipro"
  env                 = "prod"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
  tenant_id           = data.azurerm_client_config.current.tenant_id
  enable_diagnostics  = false
  name_override       = "kv-bovipro-prod"

  depends_on = [module.aks]
}

module "kv_iai_prod" {
  source = "../../modules/keyvault"

  project             = "iai"
  env                 = "prod"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
  tenant_id           = data.azurerm_client_config.current.tenant_id
  enable_diagnostics  = false
  name_override       = "kv-iai-prod"

  depends_on = [module.aks]
}

# ---------- RBAC: AKS → Secrets Officer (KVs Prod) ----------------------------
resource "azurerm_role_assignment" "aks_kv_beeai_prod" {
  scope                            = module.kv_beeai_prod.key_vault_id
  role_definition_name             = "Key Vault Secrets Officer"
  principal_id                     = module.aks.aks_identity_principal_id
  skip_service_principal_aad_check = true
  depends_on                       = [module.kv_beeai_prod, module.aks]
}

resource "azurerm_role_assignment" "aks_kv_bovipro_prod" {
  scope                            = module.kv_bovipro_prod.key_vault_id
  role_definition_name             = "Key Vault Secrets Officer"
  principal_id                     = module.aks.aks_identity_principal_id
  skip_service_principal_aad_check = true
  depends_on                       = [module.kv_bovipro_prod, module.aks]
}

resource "azurerm_role_assignment" "aks_kv_iai_prod" {
  scope                            = module.kv_iai_prod.key_vault_id
  role_definition_name             = "Key Vault Secrets Officer"
  principal_id                     = module.aks.aks_identity_principal_id
  skip_service_principal_aad_check = true
  depends_on                       = [module.kv_iai_prod, module.aks]
}

# ---------- RBAC: Terraform → Secrets Officer (KVs Prod) ----------------------
resource "azurerm_role_assignment" "terraform_kv_beeai_prod" {
  scope                = module.kv_beeai_prod.key_vault_id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [module.kv_beeai_prod]
  lifecycle { ignore_changes = [principal_id] }
}

resource "azurerm_role_assignment" "terraform_kv_bovipro_prod" {
  scope                = module.kv_bovipro_prod.key_vault_id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [module.kv_bovipro_prod]
  lifecycle { ignore_changes = [principal_id] }
}

resource "azurerm_role_assignment" "terraform_kv_iai_prod" {
  scope                = module.kv_iai_prod.key_vault_id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [module.kv_iai_prod]
  lifecycle { ignore_changes = [principal_id] }
}

# ---------- Secrets Prod — BeeAI -----------------------------------------------
resource "azurerm_key_vault_secret" "beeai_prod_pg_connection" {
  name         = "pg-connection-string"
  value        = "postgresql://pgadmin:${var.pg_admin_password}@${module.postgres.server_fqdn}:5432/beeai-prod?sslmode=require"
  key_vault_id = module.kv_beeai_prod.key_vault_id
  depends_on   = [module.kv_beeai_prod, module.postgres, azurerm_role_assignment.terraform_kv_beeai_prod]
}

resource "azurerm_key_vault_secret" "beeai_prod_appinsights" {
  name         = "appinsights-connection-string"
  value        = module.observability.app_insights_connection_string
  key_vault_id = module.kv_beeai_prod.key_vault_id
  depends_on   = [module.kv_beeai_prod, azurerm_role_assignment.terraform_kv_beeai_prod]
}

resource "azurerm_key_vault_secret" "beeai_prod_ai_foundry_endpoint" {
  name         = "ai-foundry-endpoint"
  value        = module.ai.openai_endpoint
  key_vault_id = module.kv_beeai_prod.key_vault_id
  depends_on   = [module.kv_beeai_prod, module.ai, azurerm_role_assignment.terraform_kv_beeai_prod]
}

resource "azurerm_key_vault_secret" "beeai_prod_content_safety_endpoint" {
  name         = "content-safety-endpoint"
  value        = module.ai.content_safety_endpoint
  key_vault_id = module.kv_beeai_prod.key_vault_id
  depends_on   = [module.kv_beeai_prod, module.ai, azurerm_role_assignment.terraform_kv_beeai_prod]
}

resource "azurerm_key_vault_secret" "beeai_prod_ai_deployment" {
  name         = "ai-foundry-deployment-prod"
  value        = module.ai.gpt4o_deployment_name
  key_vault_id = module.kv_beeai_prod.key_vault_id
  depends_on   = [module.kv_beeai_prod, module.ai, azurerm_role_assignment.terraform_kv_beeai_prod]
}

# ---------- Secrets Prod — BoviPro ---------------------------------------------
resource "azurerm_key_vault_secret" "bovipro_prod_pg_connection" {
  name         = "bovipro-pg-connection"
  value        = "postgresql://pgadmin:${var.pg_admin_password}@${module.postgres.server_fqdn}:5432/bovipro-prod?sslmode=require"
  key_vault_id = module.kv_bovipro_prod.key_vault_id
  depends_on   = [module.kv_bovipro_prod, module.postgres, azurerm_role_assignment.terraform_kv_bovipro_prod]
}

# ---------- Secrets Prod — IAI -------------------------------------------------
resource "azurerm_key_vault_secret" "iai_prod_pg_connection" {
  name         = "pg-connection-string"
  value        = "postgresql://pgadmin:${var.pg_admin_password}@${module.postgres.server_fqdn}:5432/iai-prod?sslmode=require"
  key_vault_id = module.kv_iai_prod.key_vault_id
  depends_on   = [module.kv_iai_prod, module.postgres, azurerm_role_assignment.terraform_kv_iai_prod]
}

resource "azurerm_key_vault_secret" "iai_prod_appinsights" {
  name         = "appinsights-connection-string"
  value        = module.observability.app_insights_connection_string
  key_vault_id = module.kv_iai_prod.key_vault_id
  depends_on   = [module.kv_iai_prod, azurerm_role_assignment.terraform_kv_iai_prod]
}

resource "azurerm_key_vault_secret" "iai_prod_openai_endpoint" {
  name         = "azure-openai-endpoint"
  value        = azurerm_cognitive_account.openai_iai.endpoint
  key_vault_id = module.kv_iai_prod.key_vault_id
  depends_on   = [module.kv_iai_prod, azurerm_cognitive_account.openai_iai, azurerm_role_assignment.terraform_kv_iai_prod]
}

resource "azurerm_key_vault_secret" "iai_prod_openai_key" {
  name         = "azure-openai-api-key"
  value        = azurerm_cognitive_account.openai_iai.primary_access_key
  key_vault_id = module.kv_iai_prod.key_vault_id
  depends_on   = [module.kv_iai_prod, azurerm_cognitive_account.openai_iai, azurerm_role_assignment.terraform_kv_iai_prod]
}

resource "azurerm_key_vault_secret" "iai_prod_device_token" {
  name         = "device-token"
  value        = var.iai_device_token
  key_vault_id = module.kv_iai_prod.key_vault_id
  depends_on   = [module.kv_iai_prod, azurerm_role_assignment.terraform_kv_iai_prod]
}

# Nota: secrets JWT para prod devem ser criados manualmente:
#   az keyvault secret set --vault-name kv-beeai-prod --name jwt-secret-key --value "$(openssl rand -base64 48)"
#   az keyvault secret set --vault-name kv-bovipro-prod --name bovipro-jwt-secret --value "$(openssl rand -base64 48)"

###############################################################################
# GETCHAT — IA de Atendimento Getnet
# Chat inteligente com RAG (Azure AI Search) + Anthropic Claude.
#
# Recursos pré-existentes (criados via az CLI) — importar antes do primeiro apply:
#
#   SUBSCRIPTION=$(az account show --query id -o tsv)
#   RG=rg-shared-dev
#
#   terraform import 'module.kv_getchat.azurerm_key_vault.main' \
#     /subscriptions/$SUBSCRIPTION/resourceGroups/$RG/providers/Microsoft.KeyVault/vaults/kv-getchat-dev
#
#   terraform import 'azurerm_search_service.getchat' \
#     /subscriptions/$SUBSCRIPTION/resourceGroups/$RG/providers/Microsoft.Search/searchServices/search-getchat-dev
#
#   terraform import 'azurerm_cognitive_account.openai_getchat' \
#     /subscriptions/$SUBSCRIPTION/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/oai-getchat-dev
###############################################################################

# ---------- Database GetChat ---------------------------------------------------
resource "azurerm_postgresql_flexible_server_database" "getchat" {
  name      = "getchat"
  server_id = module.postgres.server_id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# ---------- Key Vault GetChat --------------------------------------------------
module "kv_getchat" {
  source = "../../modules/keyvault"

  project             = "getchat"
  env                 = var.env
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
  tenant_id           = data.azurerm_client_config.current.tenant_id
  enable_diagnostics  = false
  name_override       = "kv-getchat-dev"

  depends_on = [module.aks]
}

# ---------- Azure AI Search (RAG) ---------------------------------------------
# SKU configurável via var.getchat_search_sku:
#   "free"  — $0/mês, 50MB, 3 índices, SEM vector search (demo apenas)
#   "basic" — ~$75/mês, 2GB, 15 índices, COM vector/semantic search (recomendado)
resource "azurerm_search_service" "getchat" {
  name                = "search-getchat-dev"
  resource_group_name = azurerm_resource_group.main.name
  location            = coalesce(var.getchat_search_location, var.location)
  sku                 = var.getchat_search_sku

  replica_count   = 1
  partition_count = 1

  local_authentication_enabled = true

  tags = var.tags
}

# ---------- Azure OpenAI (embeddings para ingestão RAG) -----------------------
resource "azurerm_cognitive_account" "openai_getchat" {
  name                  = "oai-getchat-dev"
  resource_group_name   = azurerm_resource_group.main.name
  location              = var.location
  kind                  = "OpenAI"
  sku_name              = "S0"
  custom_subdomain_name = "oai-getchat-dev"

  identity {
    type = "SystemAssigned"
  }

  network_acls {
    default_action = "Allow"
  }

  tags = var.tags
}

resource "azurerm_cognitive_deployment" "getchat_embeddings" {
  name                 = "text-embedding-3-small"
  cognitive_account_id = azurerm_cognitive_account.openai_getchat.id

  model {
    format  = "OpenAI"
    name    = "text-embedding-3-small"
    version = "1"
  }

  scale {
    type     = "Standard"
    capacity = 1
  }

  lifecycle {
    # Ignora o deployment legado text-embedding-ada-002 criado via az CLI.
    # O Terraform gerencia apenas o deployment definido neste bloco.
    ignore_changes = []
  }
}

# ---------- RBAC: AKS identity → Secrets Officer (KV GetChat) -----------------
resource "azurerm_role_assignment" "aks_kv_getchat" {
  scope                            = module.kv_getchat.key_vault_id
  role_definition_name             = "Key Vault Secrets Officer"
  principal_id                     = module.aks.aks_identity_principal_id
  skip_service_principal_aad_check = true
  depends_on                       = [module.kv_getchat, module.aks]
}

# ---------- RBAC: AKS kubelet identity → Secrets User (KV GetChat) ------------
# O CSI driver (SecretProviderClass) usa a kubelet identity para ler secrets —
# sem isso os pods ficam em ContainerCreating.
resource "azurerm_role_assignment" "kubelet_kv_getchat" {
  scope                            = module.kv_getchat.key_vault_id
  role_definition_name             = "Key Vault Secrets User"
  principal_id                     = module.aks.kubelet_identity_object_id
  skip_service_principal_aad_check = true
  depends_on                       = [module.kv_getchat, module.aks]
}

# ---------- RBAC: Terraform (CI/CD) → Secrets Officer (KV GetChat) ------------
resource "azurerm_role_assignment" "terraform_kv_getchat" {
  scope                = module.kv_getchat.key_vault_id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [module.kv_getchat]
  lifecycle { ignore_changes = [principal_id] }
}

# ---------- Secrets GetChat ---------------------------------------------------
resource "azurerm_key_vault_secret" "getchat_pg_connection" {
  name         = "pg-connection-string"
  value        = "postgresql+asyncpg://pgadmin:${var.pg_admin_password}@${module.postgres.server_fqdn}:5432/getchat?ssl=require"
  key_vault_id = module.kv_getchat.key_vault_id
  depends_on   = [module.kv_getchat, module.postgres, azurerm_role_assignment.terraform_kv_getchat, azurerm_postgresql_flexible_server_database.getchat]
}

resource "azurerm_key_vault_secret" "getchat_appinsights" {
  name         = "appinsights-connection-string"
  value        = module.observability.app_insights_connection_string
  key_vault_id = module.kv_getchat.key_vault_id
  depends_on   = [module.kv_getchat, azurerm_role_assignment.terraform_kv_getchat]
}

resource "azurerm_key_vault_secret" "getchat_search_endpoint" {
  name         = "ai-search-endpoint"
  value        = "https://${azurerm_search_service.getchat.name}.search.windows.net"
  key_vault_id = module.kv_getchat.key_vault_id
  depends_on   = [module.kv_getchat, azurerm_search_service.getchat, azurerm_role_assignment.terraform_kv_getchat]
}

resource "azurerm_key_vault_secret" "getchat_search_key" {
  name         = "ai-search-key"
  value        = azurerm_search_service.getchat.primary_key
  key_vault_id = module.kv_getchat.key_vault_id
  depends_on   = [module.kv_getchat, azurerm_search_service.getchat, azurerm_role_assignment.terraform_kv_getchat]
}

resource "azurerm_key_vault_secret" "getchat_oai_endpoint" {
  name         = "oai-endpoint"
  value        = azurerm_cognitive_account.openai_getchat.endpoint
  key_vault_id = module.kv_getchat.key_vault_id
  depends_on   = [module.kv_getchat, azurerm_cognitive_account.openai_getchat, azurerm_role_assignment.terraform_kv_getchat]
}

resource "azurerm_key_vault_secret" "getchat_oai_key" {
  name         = "oai-api-key"
  value        = azurerm_cognitive_account.openai_getchat.primary_access_key
  key_vault_id = module.kv_getchat.key_vault_id
  depends_on   = [module.kv_getchat, azurerm_cognitive_account.openai_getchat, azurerm_role_assignment.terraform_kv_getchat]
}

resource "azurerm_key_vault_secret" "getchat_anthropic_key" {
  name         = "anthropic-api-key"
  value        = var.getchat_anthropic_api_key
  key_vault_id = module.kv_getchat.key_vault_id
  depends_on   = [module.kv_getchat, azurerm_role_assignment.terraform_kv_getchat]
}

###############################################################################
# KEYCLOAK COMPARTILHADO
# Necessario para login do Tradux AI e demais apps que usam OIDC.
###############################################################################

# ---------- Database Keycloak --------------------------------------------------
resource "azurerm_postgresql_flexible_server_database" "keycloak" {
  name      = "keycloak"
  server_id = module.postgres.server_id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# ---------- Key Vault Keycloak -------------------------------------------------
module "kv_keycloak" {
  source = "../../modules/keyvault"

  project             = "keycloak"
  env                 = var.env
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
  tenant_id           = data.azurerm_client_config.current.tenant_id
  enable_diagnostics  = false
  name_override       = "kv-keycloak-dev"

  depends_on = [module.aks]
}

# ---------- RBAC: AKS identity -> Secrets Officer (KV Keycloak) ----------------
resource "azurerm_role_assignment" "aks_kv_keycloak" {
  scope                            = module.kv_keycloak.key_vault_id
  role_definition_name             = "Key Vault Secrets Officer"
  principal_id                     = module.aks.aks_identity_principal_id
  skip_service_principal_aad_check = true
  depends_on                       = [module.kv_keycloak, module.aks]
}

# ---------- RBAC: AKS kubelet identity -> Secrets User (CSI Driver) ------------
resource "azurerm_role_assignment" "kubelet_kv_keycloak" {
  scope                            = module.kv_keycloak.key_vault_id
  role_definition_name             = "Key Vault Secrets User"
  principal_id                     = module.aks.kubelet_identity_object_id
  skip_service_principal_aad_check = true
  depends_on                       = [module.kv_keycloak, module.aks]
}

# ---------- RBAC: Terraform (CI/CD) -> Secrets Officer -------------------------
resource "azurerm_role_assignment" "terraform_kv_keycloak" {
  scope                = module.kv_keycloak.key_vault_id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [module.kv_keycloak]
  lifecycle { ignore_changes = [principal_id] }
}

# ---------- Secrets Keycloak ---------------------------------------------------
resource "azurerm_key_vault_secret" "keycloak_admin_password" {
  name         = "keycloak-admin-password"
  value        = var.keycloak_admin_password
  key_vault_id = module.kv_keycloak.key_vault_id
  depends_on   = [module.kv_keycloak, azurerm_role_assignment.terraform_kv_keycloak]
}

resource "azurerm_key_vault_secret" "keycloak_db_password" {
  name         = "keycloak-db-password"
  value        = var.pg_admin_password
  key_vault_id = module.kv_keycloak.key_vault_id
  depends_on   = [module.kv_keycloak, module.postgres, azurerm_role_assignment.terraform_kv_keycloak]
}

# Nota: JWT secret — criar manualmente após o apply (segredo gerado localmente, não pelo Terraform):
#   az keyvault secret set --vault-name kv-getchat-dev --name jwt-secret-key --value "$(openssl rand -base64 48)"

###############################################################################
# TRADUX AI — Plataforma de tradução crítica de documentos
# Azure AI Translator + Doc Intelligence + Custom Vision + Language + Service Bus
###############################################################################

# ---------- Database Tradux AI ------------------------------------------------
resource "azurerm_postgresql_flexible_server_database" "traduxai" {
  name      = "traduxai-dev"
  server_id = module.postgres.server_id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# ---------- Key Vault Tradux AI -----------------------------------------------
module "kv_traduxai" {
  source = "../../modules/keyvault"

  project             = "traduxai"
  env                 = var.env
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
  tenant_id           = data.azurerm_client_config.current.tenant_id
  enable_diagnostics  = false
  name_override       = "kv-traduxai-dev"

  depends_on = [module.aks]
}

# ---------- RBAC: AKS identity → Secrets Officer (KV Tradux AI) ---------------
resource "azurerm_role_assignment" "aks_kv_traduxai" {
  scope                            = module.kv_traduxai.key_vault_id
  role_definition_name             = "Key Vault Secrets Officer"
  principal_id                     = module.aks.aks_identity_principal_id
  skip_service_principal_aad_check = true
  depends_on                       = [module.kv_traduxai, module.aks]
}

# ---------- RBAC: AKS kubelet identity → Secrets User (CSI Driver) ------------
resource "azurerm_role_assignment" "kubelet_kv_traduxai" {
  scope                            = module.kv_traduxai.key_vault_id
  role_definition_name             = "Key Vault Secrets User"
  principal_id                     = module.aks.kubelet_identity_object_id
  skip_service_principal_aad_check = true
  depends_on                       = [module.kv_traduxai, module.aks]
}

# ---------- RBAC: Terraform (CI/CD) → Secrets Officer -------------------------
resource "azurerm_role_assignment" "terraform_kv_traduxai" {
  scope                = module.kv_traduxai.key_vault_id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on           = [module.kv_traduxai]
  lifecycle { ignore_changes = [principal_id] }
}

# ---------- Serviços AI específicos (Translator, DocInt, Vision, Language,
#            Storage, Service Bus, Search) -------------------------------------
module "traduxai" {
  source = "../../modules/traduxai"

  resource_group_name       = azurerm_resource_group.main.name
  location                  = var.location
  environment               = var.env
  keyvault_id               = module.kv_traduxai.key_vault_id
  storage_account_name      = "sttraduxaiheckdev"
  search_sku                = "free"
  enable_search             = false
  translator_sku            = "F0"
  document_intelligence_sku = "F0"
  custom_vision_sku         = "F0"
  language_sku              = "F0"
  tags                      = var.tags

  depends_on = [
    module.kv_traduxai,
    azurerm_role_assignment.terraform_kv_traduxai,
  ]
}

# ---------- Secrets compartilhados no KV Tradux AI ----------------------------
resource "azurerm_key_vault_secret" "traduxai_pg_connection" {
  name         = "traduxai-postgres-url"
  value        = "postgresql+asyncpg://pgadmin:${var.pg_admin_password}@${module.postgres.server_fqdn}:5432/traduxai-dev?ssl=require"
  key_vault_id = module.kv_traduxai.key_vault_id
  depends_on   = [module.kv_traduxai, module.postgres, azurerm_role_assignment.terraform_kv_traduxai, azurerm_postgresql_flexible_server_database.traduxai]
}

resource "azurerm_key_vault_secret" "traduxai_appinsights" {
  name         = "traduxai-appinsights"
  value        = module.observability.app_insights_connection_string
  key_vault_id = module.kv_traduxai.key_vault_id
  depends_on   = [module.kv_traduxai, azurerm_role_assignment.terraform_kv_traduxai]
}

resource "azurerm_key_vault_secret" "traduxai_keycloak_url" {
  name         = "traduxai-keycloak-url"
  value        = "http://keycloak.keycloak.svc.cluster.local:8080"
  key_vault_id = module.kv_traduxai.key_vault_id
  depends_on   = [module.kv_traduxai, azurerm_role_assignment.terraform_kv_traduxai]
}

resource "azurerm_key_vault_secret" "traduxai_keycloak_issuer" {
  name         = "traduxai-keycloak-issuer"
  value        = "http://keycloak.keycloak.svc.cluster.local:8080/realms/traduxai"
  key_vault_id = module.kv_traduxai.key_vault_id
  depends_on   = [module.kv_traduxai, azurerm_role_assignment.terraform_kv_traduxai]
}

resource "azurerm_key_vault_secret" "traduxai_keycloak_client_secret" {
  name         = "traduxai-keycloak-client-secret"
  value        = var.traduxai_keycloak_client_secret
  key_vault_id = module.kv_traduxai.key_vault_id
  depends_on   = [module.kv_traduxai, azurerm_role_assignment.terraform_kv_traduxai]
}

resource "azurerm_key_vault_secret" "traduxai_nextauth_secret" {
  name         = "traduxai-nextauth-secret"
  value        = var.traduxai_nextauth_secret
  key_vault_id = module.kv_traduxai.key_vault_id
  depends_on   = [module.kv_traduxai, azurerm_role_assignment.terraform_kv_traduxai]
}

resource "azurerm_key_vault_secret" "traduxai_openai_endpoint" {
  name         = "traduxai-openai-endpoint"
  value        = module.ai.openai_endpoint
  key_vault_id = module.kv_traduxai.key_vault_id
  depends_on   = [module.kv_traduxai, module.ai, azurerm_role_assignment.terraform_kv_traduxai]
}

resource "azurerm_key_vault_secret" "traduxai_openai_key" {
  name         = "traduxai-openai-key"
  value        = module.ai.openai_primary_key
  key_vault_id = module.kv_traduxai.key_vault_id
  depends_on   = [module.kv_traduxai, module.ai, azurerm_role_assignment.terraform_kv_traduxai]
}

# Nota: após o apply, importar o realm Tradux AI no Keycloak compartilhado:
#   kubectl port-forward -n keycloak svc/keycloak 8080:8080
#   # Upload realm-traduxai-dev.json via admin console → http://localhost:8080/admin

###############################################################################
# ADICIONANDO UMA NOVA APLICAÇÃO
# Copie e adapte o bloco abaixo para cada nova app:
#
# 1. Database:
#    resource "azurerm_postgresql_flexible_server_database" "novaapp" { ... }
#
# 2. Key Vault:
#    module "kv_novaapp" { source = "../../modules/keyvault" ... }
#    resource "azurerm_role_assignment" "aks_kv_novaapp"      { ... }
#    resource "azurerm_role_assignment" "terraform_kv_novaapp" { ... }
#
# 3. Connection string no KV:
#    resource "azurerm_key_vault_secret" "novaapp_pg_connection" { ... }
#
# 4. Manifestos K8s em: Infra/k8s/novaapp/
# 5. Workflow de deploy no repo da app: .github/workflows/deploy-dev.yml
###############################################################################
