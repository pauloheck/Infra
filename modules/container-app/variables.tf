variable "resource_prefix" {
  description = "Prefixo para nomes dos recursos (ex: iai)"
  type        = string
}

variable "env" {
  description = "Ambiente (dev ou prd)"
  type        = string
}

variable "location" {
  description = "Região Azure"
  type        = string
}

variable "container_image" {
  description = "Imagem Docker completa (ex: iaiacrdev.azurecr.io/iai-core:latest)"
  type        = string
}

variable "container_cpu" {
  description = "CPU do container (ex: 0.5)"
  type        = number
  default     = 0.5
}

variable "container_memory" {
  description = "Memória do container (ex: 1Gi)"
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

variable "openai_endpoint" {
  description = "Endpoint do Azure OpenAI (passado pelo módulo openai)"
  type        = string
  default     = ""
}

variable "openai_api_key" {
  description = "API Key do Azure OpenAI"
  type        = string
  sensitive   = true
  default     = ""
}

variable "openai_deployment" {
  description = "Nome do deployment do modelo Azure OpenAI (ex: gpt-4o-mini)"
  type        = string
  default     = "gpt-4o-mini"
}

variable "device_token" {
  description = "Token de autenticação do device (MVP)"
  type        = string
  sensitive   = true
  default     = "devtoken-local"
}
