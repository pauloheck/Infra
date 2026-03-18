###############################################################################
# Module: network
# VNet + Subnets + NSGs
###############################################################################

variable "project" { type = string }
variable "env" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "tags" { type = map(string) }

variable "vnet_address_space" {
  type    = list(string)
  default = ["10.0.0.0/16"]
}

variable "subnet_aks_prefix" {
  type    = list(string)
  default = ["10.0.0.0/20"]
}

variable "subnet_data_prefix" {
  type    = list(string)
  default = ["10.0.16.0/24"]
}

variable "subnet_pe_prefix" {
  type    = list(string)
  default = ["10.0.17.0/24"]
}

variable "subnet_appgw_prefix" {
  type    = list(string)
  default = ["10.0.18.0/24"]
}

# ---------- VNet --------------------------------------------------------------
resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.project}-${var.env}"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.vnet_address_space
  tags                = var.tags
}

# ---------- Subnets -----------------------------------------------------------
resource "azurerm_subnet" "aks" {
  name                 = "snet-aks"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = var.subnet_aks_prefix
}

resource "azurerm_subnet" "data" {
  name                 = "snet-data"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = var.subnet_data_prefix

  delegation {
    name = "fs"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-private-endpoints"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = var.subnet_pe_prefix
}

resource "azurerm_subnet" "appgw" {
  name                 = "snet-appgw"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = var.subnet_appgw_prefix
}

# ---------- NSG (AKS) --------------------------------------------------------
resource "azurerm_network_security_group" "aks" {
  name                = "nsg-aks-${var.project}-${var.env}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = azurerm_network_security_group.aks.id
}

# ---------- NSG (Data) -------------------------------------------------------
resource "azurerm_network_security_group" "data" {
  name                = "nsg-data-${var.project}-${var.env}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "data" {
  subnet_id                 = azurerm_subnet.data.id
  network_security_group_id = azurerm_network_security_group.data.id
}

# ---------- Outputs -----------------------------------------------------------
output "vnet_id" {
  value = azurerm_virtual_network.main.id
}

output "vnet_name" {
  value = azurerm_virtual_network.main.name
}

output "subnet_aks_id" {
  value = azurerm_subnet.aks.id
}

output "subnet_data_id" {
  value = azurerm_subnet.data.id
}

output "subnet_pe_id" {
  value = azurerm_subnet.private_endpoints.id
}

output "subnet_appgw_id" {
  value = azurerm_subnet.appgw.id
}
