###############################################################################
# Module: AI – Variables
###############################################################################

variable "project" {
  type = string
}

variable "env" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "aks_identity_principal_id" {
  type        = string
  description = "Object ID of the AKS system-assigned identity (control plane)."
}

variable "kubelet_identity_object_id" {
  type        = string
  description = "Object ID of the AKS kubelet user-assigned identity (used by pods via IMDS)."
}

variable "key_vault_id" {
  type        = string
  description = "Key Vault ID where AI endpoints/keys will be stored."
}

variable "gpt4o_version" {
  type    = string
  default = "2024-11-20"
}

variable "gpt4o_capacity" {
  type        = number
  default     = 10
  description = "Capacity in thousands of tokens per minute (TPM). 10 = 10K TPM."
}

variable "gpt4o_mini_version" {
  type    = string
  default = "2024-07-18"
}

variable "gpt4o_mini_capacity" {
  type        = number
  default     = 10
  description = "gpt-4o-mini capacity in K TPM. 10 = 10K TPM."
}

variable "openai_name_override" {
  type        = string
  default     = ""
  description = "Nome customizado para o Azure OpenAI (substitui oai-{project}-{env})."
}

variable "content_safety_name_override" {
  type        = string
  default     = ""
  description = "Nome customizado para o Content Safety (substitui cs-{project}-{env})."
}
