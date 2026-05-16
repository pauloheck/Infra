variable "resource_group_name" {
  type = string
}

variable "location" {
  type    = string
  default = "eastus2"
}

variable "environment" {
  type = string
}

variable "prefix" {
  type    = string
  default = "traduxai"
}

variable "keyvault_id" {
  type        = string
  description = "ID do Key Vault criado em main.tf — secrets são armazenados aqui"
}

variable "storage_account_name" {
  type        = string
  description = "Nome globalmente único para a Storage Account (3-24 chars, lowercase)"
}

variable "search_sku" {
  type    = string
  default = "free"
}

variable "enable_search" {
  type    = bool
  default = true
}

variable "translator_sku" {
  type    = string
  default = "F0"
}

variable "document_intelligence_sku" {
  type    = string
  default = "F0"
}

variable "custom_vision_sku" {
  type    = string
  default = "F0"
}

variable "language_sku" {
  type    = string
  default = "F0"
}

variable "tags" {
  type    = map(string)
  default = {}
}
