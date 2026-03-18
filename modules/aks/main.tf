###############################################################################
# Module: aks
# Azure Kubernetes Service + Managed Identity + Container Insights
###############################################################################

variable "project" { type = string }
variable "env" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "tags" { type = map(string) }

variable "kubernetes_version" {
  type    = string
  default = "1.29"
}

variable "subnet_id" { type = string }

variable "log_analytics_workspace_id" {
  type    = string
  default = ""
}

variable "acr_id" {
  type    = string
  default = ""
}

variable "enable_diagnostics" {
  type    = bool
  default = true
}

variable "enable_acr_pull" {
  type    = bool
  default = true
}

variable "enable_workload_identity" {
  type        = bool
  default     = true
  description = "Enable OIDC issuer and Workload Identity on the cluster (required for pod-level Azure auth)."
}

# --- System node pool --------------------------------------------------------
variable "system_node_count" {
  type    = number
  default = 2
}

variable "system_vm_size" {
  type    = string
  default = "Standard_D2s_v5"
}

# --- User node pool ----------------------------------------------------------
variable "user_node_min" {
  type    = number
  default = 1
}

variable "user_node_max" {
  type    = number
  default = 5
}

variable "user_vm_size" {
  type    = string
  default = "Standard_D4s_v5"
}

variable "dns_prefix" {
  type    = string
  default = ""
}

variable "enable_user_pool" {
  type        = bool
  default     = true
  description = "Cria pool de nós separado para workloads. false = workloads rodam no pool system (ideal para envs mínimos)."
}

# ---------- AKS Cluster ------------------------------------------------------
resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-${var.project}-${var.env}"
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.dns_prefix != "" ? var.dns_prefix : "aks-${var.project}-${var.env}"
  kubernetes_version  = var.kubernetes_version
  tags                = var.tags

  default_node_pool {
    name                = "system"
    node_count          = var.system_node_count
    vm_size             = var.system_vm_size
    vnet_subnet_id      = var.subnet_id
    os_disk_size_gb     = 50
    type                = "VirtualMachineScaleSets"
    enable_auto_scaling = false

    tags = var.tags
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "calico"
    load_balancer_sku = "standard"
    service_cidr      = "10.1.0.0/16"
    dns_service_ip    = "10.1.0.10"
  }

  # Container Insights
  dynamic "oms_agent" {
    for_each = var.enable_diagnostics ? [1] : []
    content {
      log_analytics_workspace_id = var.log_analytics_workspace_id
    }
  }

  azure_active_directory_role_based_access_control {
    managed            = true
    azure_rbac_enabled = true
  }

  oidc_issuer_enabled       = var.enable_workload_identity
  workload_identity_enabled = var.enable_workload_identity

  # CSI Driver para Azure Key Vault (necessário para SecretProviderClass)
  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }
}

# ---------- User node pool (opcional) ----------------------------------------
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  count                 = var.enable_user_pool ? 1 : 0
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.user_vm_size
  vnet_subnet_id        = var.subnet_id
  os_disk_size_gb       = 100
  enable_auto_scaling   = true
  min_count             = var.user_node_min
  max_count             = var.user_node_max
  mode                  = "User"
  tags                  = var.tags

  upgrade_settings {
    max_surge                     = "10%"
    drain_timeout_in_minutes      = 0
    node_soak_duration_in_minutes = 0
  }
}

# ---------- ACR pull role assignment ------------------------------------------
resource "azurerm_role_assignment" "aks_acr_pull" {
  count = var.enable_acr_pull ? 1 : 0

  principal_id                     = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = var.acr_id
  skip_service_principal_aad_check = true
}

# ---------- Diagnostic Settings -----------------------------------------------
resource "azurerm_monitor_diagnostic_setting" "aks" {
  count = var.enable_diagnostics ? 1 : 0

  name                       = "diag-aks-${var.project}-${var.env}"
  target_resource_id         = azurerm_kubernetes_cluster.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "kube-apiserver"
  }

  enabled_log {
    category = "kube-controller-manager"
  }

  # kube-audit-admin: only write/mutating ops (create/delete/patch)
  # Replaces kube-audit (all calls) — eliminates 60-80% of AzureDiagnostics volume
  # Removed: kube-scheduler (low value, high noise), guard (AAD noise), kube-audit (all reads)
  enabled_log {
    category = "kube-audit-admin"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# ---------- Outputs -----------------------------------------------------------
output "aks_id" {
  value = azurerm_kubernetes_cluster.main.id
}

output "aks_name" {
  value = azurerm_kubernetes_cluster.main.name
}

output "aks_fqdn" {
  value = azurerm_kubernetes_cluster.main.fqdn
}

output "kubelet_identity_object_id" {
  value = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

output "aks_identity_principal_id" {
  value = azurerm_kubernetes_cluster.main.identity[0].principal_id
}

output "kube_config_raw" {
  value     = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive = true
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL — used to create federated identity credentials for Workload Identity."
  value       = var.enable_workload_identity ? azurerm_kubernetes_cluster.main.oidc_issuer_url : ""
}
