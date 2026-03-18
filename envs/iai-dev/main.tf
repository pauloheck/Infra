###############################################################################
# IAI Dev — Azure Container Apps
#
# Recursos criados (isolados no rg-iai-dev):
#   rg-iai-dev              Resource Group exclusivo IAI
#   cae-iai-dev             Container Apps Environment
#   ca-iai-core-dev         Container App (FastAPI + LangGraph)
#   oai-iai-dev             Azure OpenAI (gpt-4o-mini)
#
# Recursos COMPARTILHADOS com shared-dev (reutilizados, não criados aqui):
#   acrheckiodev            ACR — imagens IAI vão para o mesmo registry
#   law-shared-dev          Log Analytics — observabilidade unificada
#
# Custo incremental IAI: ~$0 idle (Container Apps escala para 0)
#   + Azure OpenAI: pay-per-token
###############################################################################

terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  use_oidc = true
}

# ---------- Resource Group próprio IAI ----------------------------------------
resource "azurerm_resource_group" "iai" {
  name     = "rg-iai-${var.env}"
  location = var.location
  tags     = local.tags
}

# ---------- Referência ao ACR compartilhado -----------------------------------
# IAI usa o mesmo ACR da plataforma (acrheckiodev) — sem custo adicional.
data "azurerm_container_registry" "shared" {
  name                = "acrheckiodev"
  resource_group_name = "rg-shared-dev"
}

# ---------- Referência ao Log Analytics compartilhado -------------------------
data "azurerm_log_analytics_workspace" "shared" {
  name                = "law-shared-dev"
  resource_group_name = "rg-shared-dev"
}

# ---------- Managed Identity para puxar imagens do ACR compartilhado ---------
resource "azurerm_user_assigned_identity" "iai" {
  name                = "id-iai-${var.env}"
  resource_group_name = azurerm_resource_group.iai.name
  location            = azurerm_resource_group.iai.location
  tags                = local.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = data.azurerm_container_registry.shared.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.iai.principal_id
}

# ---------- Application Insights (vinculado ao Law compartilhado) ------------
resource "azurerm_application_insights" "iai" {
  name                = "appi-iai-${var.env}"
  resource_group_name = azurerm_resource_group.iai.name
  location            = azurerm_resource_group.iai.location
  workspace_id        = data.azurerm_log_analytics_workspace.shared.id
  application_type    = "web"
  tags                = local.tags
}

# ---------- Azure OpenAI (exclusivo IAI) -------------------------------------
resource "azurerm_cognitive_account" "openai" {
  name                  = "oai-iai-${var.env}"
  resource_group_name   = azurerm_resource_group.iai.name
  location              = var.openai_location
  kind                  = "OpenAI"
  sku_name              = "S0"
  custom_subdomain_name = "oai-iai-${var.env}"

  identity {
    type = "SystemAssigned"
  }

  network_acls {
    default_action = "Allow"
  }

  tags = local.tags
}

resource "azurerm_cognitive_deployment" "gpt4o_mini" {
  name                 = "gpt-4o-mini"
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = "gpt-4o-mini"
    version = "2024-07-18"
  }

  sku {
    name     = "Standard"
    capacity = 10
  }
}

# ---------- Container Apps Environment ---------------------------------------
resource "azurerm_container_app_environment" "iai" {
  name                       = "cae-iai-${var.env}"
  resource_group_name        = azurerm_resource_group.iai.name
  location                   = azurerm_resource_group.iai.location
  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.shared.id
  tags                       = local.tags
}

# ---------- Container App — Core ---------------------------------------------
resource "azurerm_container_app" "core" {
  name                         = "ca-iai-core-${var.env}"
  container_app_environment_id = azurerm_container_app_environment.iai.id
  resource_group_name          = azurerm_resource_group.iai.name
  revision_mode                = "Single"
  tags                         = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.iai.id]
  }

  registry {
    server   = data.azurerm_container_registry.shared.login_server
    identity = azurerm_user_assigned_identity.iai.id
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    container {
      name   = "iai-core"
      image  = var.container_image
      cpu    = var.container_cpu
      memory = var.container_memory

      env {
        name  = "ENV"
        value = var.env
      }
      env {
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = azurerm_application_insights.iai.connection_string
      }
      env {
        name  = "AZURE_OPENAI_ENDPOINT"
        value = azurerm_cognitive_account.openai.endpoint
      }
      env {
        name  = "AZURE_OPENAI_API_KEY"
        value = azurerm_cognitive_account.openai.primary_access_key
      }
      env {
        name  = "AZURE_OPENAI_DEPLOYMENT"
        value = var.openai_deployment
      }
      env {
        name  = "DEVICE_TOKEN"
        value = var.device_token
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = 8000
    transport        = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
}

# ---------- Locals -----------------------------------------------------------
locals {
  tags = {
    project    = "iai"
    env        = var.env
    managed_by = "terraform"
  }
}

# ---------- Outputs ----------------------------------------------------------
output "container_app_url" {
  value       = "https://${azurerm_container_app.core.ingress[0].fqdn}"
  description = "URL pública do Container App IAI"
}

output "acr_login_server" {
  value       = data.azurerm_container_registry.shared.login_server
  description = "ACR compartilhado (acrheckiodev.azurecr.io)"
}

output "openai_endpoint" {
  value = azurerm_cognitive_account.openai.endpoint
}
