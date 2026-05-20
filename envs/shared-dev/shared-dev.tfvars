# Infra mínima compartilhada — BeeAI + BoviPro + IAI
# Aplicar: cd infra/envs/shared-dev && TF_VAR_pg_admin_password="..." terraform apply -var-file="shared-dev.tfvars" -auto-approve

project  = "shared"
env      = "dev"
location = "eastus2"

tags = {
  project   = "shared"
  env       = "dev"
  managedBy = "terraform"
  apps      = "beeai,bovipro,iai,getchat,traduxai"
}

# --- Network -----------------------------------------------------------------
vnet_address_space  = ["10.10.0.0/16"]
subnet_aks_prefix   = ["10.10.0.0/20"]
subnet_data_prefix  = ["10.10.16.0/24"]
subnet_pe_prefix    = ["10.10.17.0/24"]
subnet_appgw_prefix = ["10.10.18.0/24"]

# --- AKS (2 nós para suportar todos os projetos simultaneamente) ---------------
kubernetes_version = "1.33"
system_node_count  = 2
system_vm_size     = "Standard_D2als_v7" # 2 vCPU / 4 GB RAM — AMD v7, ~$82/mês rodando / ~$14/mês parado

# --- PostgreSQL (B1ms compartilhado) -----------------------------------------
pg_sku        = "B_Standard_B1ms"
pg_storage_mb = 32768

# --- Observability -----------------------------------------------------------
log_retention_days = 30 # mínimo do SKU PerGB2018

# --- Azure OpenAI (BeeAI) ----------------------------------------------------
ai_gpt4o_capacity      = 1
ai_gpt4o_mini_capacity = 1

# --- GetChat -----------------------------------------------------------------
getchat_search_sku      = "free"   # free=$0 (demo), basic=~$75/mês (produção com vector search)
getchat_search_location = "eastus" # eastus2 sem capacidade free — usando eastus

# --- Variáveis sensíveis (NÃO commitar valores reais) -------------------------
# Usar scripts/.env (gitignored) ou TF_VAR_* no ambiente / GitHub Secrets:
#
#   TF_VAR_pg_admin_password         — senha do PostgreSQL
#   TF_VAR_iai_device_token          — token de autenticação IAI
#   TF_VAR_getchat_anthropic_api_key — Anthropic API key (GetChat)
#
# Ver scripts/.env.example para o template.
