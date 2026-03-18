###############################################################################
# Module: AI — Azure OpenAI + Content Safety
#
# Cria:
#   - Azure OpenAI (GPT-4o deployment)
#   - Azure Content Safety
#   - RBAC: AKS identity → Cognitive Services User em ambos
###############################################################################

# ── Azure OpenAI ──────────────────────────────────────────────────────────────

locals {
  openai_name         = var.openai_name_override != "" ? var.openai_name_override : "oai-${var.project}-${var.env}"
  content_safety_name = var.content_safety_name_override != "" ? var.content_safety_name_override : "cs-${var.project}-${var.env}"
}

resource "azurerm_cognitive_account" "openai" {
  name                = local.openai_name
  location            = var.location
  resource_group_name = var.resource_group_name
  kind                = "OpenAI"
  sku_name            = "S0"

  custom_subdomain_name = local.openai_name

  tags = var.tags
}

resource "azurerm_cognitive_deployment" "gpt4o" {
  name                 = "gpt-4o"
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = "gpt-4o"
    version = var.gpt4o_version
  }

  scale {
    type     = "Standard"
    capacity = var.gpt4o_capacity
  }
}

resource "azurerm_cognitive_deployment" "gpt4o_mini" {
  name                 = "gpt-4o-mini"
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = "gpt-4o-mini"
    version = var.gpt4o_mini_version
  }

  scale {
    type     = "Standard"
    capacity = var.gpt4o_mini_capacity
  }
}

# ── Content Safety ────────────────────────────────────────────────────────────

resource "azurerm_cognitive_account" "content_safety" {
  name                = local.content_safety_name
  location            = var.location
  resource_group_name = var.resource_group_name
  kind                = "ContentSafety"
  sku_name            = "S0"

  custom_subdomain_name = local.content_safety_name

  tags = var.tags
}

# ── RBAC: kubelet identity → Cognitive Services User (pods via IMDS) ──────────
# Pods usam a kubelet identity via IMDS — não a system-assigned identity do AKS.
# aks_identity_principal_id = control plane (não usado por pods)
# kubelet_identity_object_id = node pool user-assigned identity (usada por pods)

resource "azurerm_role_assignment" "kubelet_openai" {
  scope                            = azurerm_cognitive_account.openai.id
  role_definition_name             = "Cognitive Services OpenAI User"
  principal_id                     = var.kubelet_identity_object_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "kubelet_content_safety" {
  scope                            = azurerm_cognitive_account.content_safety.id
  role_definition_name             = "Cognitive Services User"
  principal_id                     = var.kubelet_identity_object_id
  skip_service_principal_aad_check = true
}
