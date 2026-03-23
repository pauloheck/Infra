# Infra mínima compartilhada — BeeAI + BoviPro + IAI
# Aplicar: cd infra/envs/shared-dev && TF_VAR_pg_admin_password="..." terraform apply -var-file="shared-dev.tfvars" -auto-approve

project  = "shared"
env      = "dev"
location = "eastus2"

tags = {
  project   = "shared"
  env       = "dev"
  managedBy = "terraform"
  apps      = "beeai,bovipro,iai"
}

# --- Network -----------------------------------------------------------------
vnet_address_space  = ["10.10.0.0/16"]
subnet_aks_prefix   = ["10.10.0.0/20"]
subnet_data_prefix  = ["10.10.16.0/24"]
subnet_pe_prefix    = ["10.10.17.0/24"]
subnet_appgw_prefix = ["10.10.18.0/24"]

# --- AKS (1 nó, sem user pool) -----------------------------------------------
kubernetes_version = "1.32"
system_node_count  = 1
system_vm_size     = "Standard_D2s_v3"  # 2 vCPU / 8 GB RAM — B2ms sem quota AKS nesta subscription

# --- PostgreSQL (B1ms compartilhado) -----------------------------------------
pg_sku        = "B_Standard_B1ms"
pg_storage_mb = 32768

# --- Observability -----------------------------------------------------------
log_retention_days = 30

# --- Azure OpenAI (BeeAI) ----------------------------------------------------
ai_gpt4o_capacity      = 10
ai_gpt4o_mini_capacity = 10

# --- Application Gateway (BoviPro) --- IPs internos dos Internal LBs ----------
bovipro_dev_internal_ip  = "10.10.15.200"
bovipro_prod_internal_ip = "10.10.15.201"

# --- IAI device token (passado via TF_VAR_iai_device_token ou GitHub Secret) ---
# iai_device_token = "..." # NÃO commitar — usar TF_VAR_iai_device_token no CI/CD
