###############################################################################
# Module: core – Container Apps + ACR + Log Analytics + App Insights + Identity
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

# ---------------------------------------------------------------------------
# Resource Group
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "core" {
  name     = "rg-${var.resource_prefix}-${var.env}"
  location = var.location

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Log Analytics Workspace
# ---------------------------------------------------------------------------
resource "azurerm_log_analytics_workspace" "core" {
  name                = "law-${var.resource_prefix}-${var.env}"
  resource_group_name = azurerm_resource_group.core.name
  location            = azurerm_resource_group.core.location
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Application Insights
# ---------------------------------------------------------------------------
resource "azurerm_application_insights" "core" {
  name                = "ai-${var.resource_prefix}-${var.env}"
  resource_group_name = azurerm_resource_group.core.name
  location            = azurerm_resource_group.core.location
  workspace_id        = azurerm_log_analytics_workspace.core.id
  application_type    = "web"

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Azure Container Registry
# ---------------------------------------------------------------------------
resource "azurerm_container_registry" "core" {
  name                = "${var.resource_prefix}acr${var.env}"
  resource_group_name = azurerm_resource_group.core.name
  location            = azurerm_resource_group.core.location
  sku                 = "Basic"
  admin_enabled       = false

  tags = local.tags
}

# ---------------------------------------------------------------------------
# User-Assigned Managed Identity (para Container App puxar imagens do ACR)
# ---------------------------------------------------------------------------
resource "azurerm_user_assigned_identity" "core" {
  name                = "id-${var.resource_prefix}-${var.env}"
  resource_group_name = azurerm_resource_group.core.name
  location            = azurerm_resource_group.core.location

  tags = local.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.core.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.core.principal_id
}

# ---------------------------------------------------------------------------
# Container Apps Environment
# ---------------------------------------------------------------------------
resource "azurerm_container_app_environment" "core" {
  name                       = "cae-${var.resource_prefix}-${var.env}"
  resource_group_name        = azurerm_resource_group.core.name
  location                   = azurerm_resource_group.core.location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.core.id

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Container App – Core (FastAPI + WebSocket + LangGraph)
# ---------------------------------------------------------------------------
resource "azurerm_container_app" "core" {
  name                         = "ca-${var.resource_prefix}-core-${var.env}"
  container_app_environment_id = azurerm_container_app_environment.core.id
  resource_group_name          = azurerm_resource_group.core.name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.core.id]
  }

  registry {
    server   = azurerm_container_registry.core.login_server
    identity = azurerm_user_assigned_identity.core.id
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
        value = azurerm_application_insights.core.connection_string
      }

      env {
        name  = "AZURE_OPENAI_ENDPOINT"
        value = var.openai_endpoint
      }

      env {
        name  = "AZURE_OPENAI_API_KEY"
        value = var.openai_api_key
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

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Locals
# ---------------------------------------------------------------------------
locals {
  tags = {
    environment = var.env
    project     = var.resource_prefix
    managed_by  = "terraform"
  }
}
