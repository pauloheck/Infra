###############################################################################
# Variables – Dev
###############################################################################

variable "resource_prefix" {
  description = "Prefixo para nomes dos recursos"
  type        = string
  default     = "iai"
}

variable "env" {
  description = "Ambiente"
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Região principal Azure"
  type        = string
  default     = "eastus2"
}

variable "openai_location" {
  description = "Região do Azure OpenAI (pode diferir da principal)"
  type        = string
  default     = "eastus2"
}

variable "container_image" {
  description = "Imagem Docker completa (ACR + tag)"
  type        = string
}

variable "container_cpu" {
  description = "CPU do container"
  type        = number
  default     = 0.5
}

variable "container_memory" {
  description = "Memória do container"
  type        = string
  default     = "1Gi"
}

variable "min_replicas" {
  description = "Mínimo de réplicas"
  type        = number
  default     = 0
}

variable "max_replicas" {
  description = "Máximo de réplicas"
  type        = number
  default     = 3
}

variable "openai_deployment" {
  description = "Nome do deployment do modelo Azure OpenAI"
  type        = string
  default     = "gpt-4o-mini"
}

variable "device_token" {
  description = "Token de autenticação do device (MVP)"
  type        = string
  sensitive   = true
  default     = "devtoken-local"
}
