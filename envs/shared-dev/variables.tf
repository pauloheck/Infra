###############################################################################
# Shared Dev — Variables
###############################################################################

variable "project" {
  type    = string
  default = "shared"
}

variable "env" {
  type    = string
  default = "dev"
}

variable "location" {
  type    = string
  default = "eastus2"
}

variable "tags" {
  type = map(string)
  default = {
    project   = "shared"
    env       = "dev"
    managedBy = "terraform"
  }
}

# --- Network -----------------------------------------------------------------
variable "vnet_address_space" {
  type    = list(string)
  default = ["10.10.0.0/16"]
}

variable "subnet_aks_prefix" {
  type    = list(string)
  default = ["10.10.0.0/20"]
}

variable "subnet_data_prefix" {
  type    = list(string)
  default = ["10.10.16.0/24"]
}

variable "subnet_pe_prefix" {
  type    = list(string)
  default = ["10.10.17.0/24"]
}

variable "subnet_appgw_prefix" {
  type    = list(string)
  default = ["10.10.18.0/24"]
}

# --- AKS ---------------------------------------------------------------------
variable "kubernetes_version" {
  type    = string
  default = "1.32"
}

variable "system_node_count" {
  type        = number
  default     = 1
  description = "Nós no pool system. Único pool (sem user pool) para custo mínimo."
}

variable "system_vm_size" {
  type        = string
  default     = "Standard_B2ms"
  description = "2 vCPU / 8 GB RAM — comporta todos os serviços BeeAI + BoviPro em fase de construção."
}

# --- PostgreSQL ---------------------------------------------------------------
variable "pg_admin_password" {
  type      = string
  sensitive = true
}

variable "pg_sku" {
  type    = string
  default = "B_Standard_B1ms"
}

variable "pg_storage_mb" {
  type    = number
  default = 32768
}

# --- Observability ------------------------------------------------------------
variable "log_retention_days" {
  type    = number
  default = 7
}

# --- AI (BeeAI only) ---------------------------------------------------------
variable "ai_gpt4o_capacity" {
  type        = number
  default     = 10
  description = "GPT-4o capacity em K TPM."
}

variable "ai_gpt4o_mini_capacity" {
  type        = number
  default     = 10
  description = "GPT-4o-mini capacity em K TPM."
}

# --- Application Gateway (BoviPro) --------------------------------------------
variable "bovipro_dev_internal_ip" {
  type        = string
  default     = "10.10.15.200"
  description = "IP interno (snet-aks) do Internal LB bovipro-dev gateway"
}

variable "bovipro_prod_internal_ip" {
  type        = string
  default     = "10.10.15.201"
  description = "IP interno (snet-aks) do Internal LB bovipro-prod gateway"
}

# --- IAI -----------------------------------------------------------------------
variable "iai_device_token" {
  type        = string
  sensitive   = true
  description = "Token de autenticação do device IAI (MVP)."
}
