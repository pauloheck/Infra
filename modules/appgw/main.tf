###############################################################################
# Module: appgw
# Application Gateway v2 + WAF Policy + Static Public IP
#
# Roteamento por host:
#   bovipro.com.br       → backend pool prod (Internal LB)
#   dev.bovipro.com.br   → backend pool dev  (Internal LB)
#   Acesso direto por IP → backend pool prod (fallback)
#
# Health probe usa /gateway-health (endpoint do NGINX gateway).
###############################################################################

variable "project" { type = string }
variable "env" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "tags" { type = map(string) }
variable "subnet_appgw_id" { type = string }

variable "bovipro_dev_internal_ip" {
  type        = string
  description = "IP interno (snet-aks) do Internal LB bovipro-dev gateway"
  default     = "10.10.15.200"
}

variable "bovipro_prod_internal_ip" {
  type        = string
  description = "IP interno (snet-aks) do Internal LB bovipro-prod gateway"
  default     = "10.10.15.201"
}

variable "domain_prod" {
  type    = string
  default = "bovipro.com.br"
}

variable "domain_dev" {
  type    = string
  default = "dev.bovipro.com.br"
}

# ---------- Static Public IP -------------------------------------------------
resource "azurerm_public_ip" "appgw" {
  name                = "pip-appgw-${var.project}-${var.env}"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = var.tags
}

# ---------- WAF Policy (OWASP 3.2, Prevention) ------------------------------
resource "azurerm_web_application_firewall_policy" "main" {
  name                = "wafpol-${var.project}-${var.env}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  policy_settings {
    enabled                     = true
    mode                        = "Prevention"
    request_body_check          = true
    max_request_body_size_in_kb = 128
    file_upload_limit_in_mb     = 100
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
  }
}

# ---------- Application Gateway v2 (WAF_v2) ---------------------------------
resource "azurerm_application_gateway" "main" {
  name                = "appgw-${var.project}-${var.env}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
  firewall_policy_id  = azurerm_web_application_firewall_policy.main.id

  sku {
    name = "WAF_v2"
    tier = "WAF_v2"
  }

  autoscale_configuration {
    min_capacity = 0
    max_capacity = 2
  }

  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101"
  }

  gateway_ip_configuration {
    name      = "appgw-ip-config"
    subnet_id = var.subnet_appgw_id
  }

  # ── Frontend ────────────────────────────────────────────────────────────────
  frontend_ip_configuration {
    name                 = "feip-public"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  frontend_port {
    name = "port-80"
    port = 80
  }

  # ── Backend Pools ──────────────────────────────────────────────────────────
  backend_address_pool {
    name         = "pool-bovipro-prod"
    ip_addresses = [var.bovipro_prod_internal_ip]
  }

  backend_address_pool {
    name         = "pool-bovipro-dev"
    ip_addresses = [var.bovipro_dev_internal_ip]
  }

  # ── Backend HTTP Settings ──────────────────────────────────────────────────
  backend_http_settings {
    name                  = "http-settings-bovipro"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 300
    probe_name            = "probe-gateway-health"
  }

  # ── Health Probe ───────────────────────────────────────────────────────────
  probe {
    name                                      = "probe-gateway-health"
    protocol                                  = "Http"
    path                                      = "/gateway-health"
    host                                      = "127.0.0.1"
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = false
  }

  # ── Listeners (host-based routing) ─────────────────────────────────────────
  http_listener {
    name                           = "listener-bovipro-prod"
    frontend_ip_configuration_name = "feip-public"
    frontend_port_name             = "port-80"
    protocol                       = "Http"
    host_name                      = var.domain_prod
  }

  http_listener {
    name                           = "listener-bovipro-dev"
    frontend_ip_configuration_name = "feip-public"
    frontend_port_name             = "port-80"
    protocol                       = "Http"
    host_name                      = var.domain_dev
  }

  http_listener {
    name                           = "listener-default"
    frontend_ip_configuration_name = "feip-public"
    frontend_port_name             = "port-80"
    protocol                       = "Http"
  }

  # ── Routing Rules ──────────────────────────────────────────────────────────
  request_routing_rule {
    name                       = "rule-bovipro-prod"
    priority                   = 100
    rule_type                  = "Basic"
    http_listener_name         = "listener-bovipro-prod"
    backend_address_pool_name  = "pool-bovipro-prod"
    backend_http_settings_name = "http-settings-bovipro"
  }

  request_routing_rule {
    name                       = "rule-bovipro-dev"
    priority                   = 200
    rule_type                  = "Basic"
    http_listener_name         = "listener-bovipro-dev"
    backend_address_pool_name  = "pool-bovipro-dev"
    backend_http_settings_name = "http-settings-bovipro"
  }

  request_routing_rule {
    name                       = "rule-default"
    priority                   = 300
    rule_type                  = "Basic"
    http_listener_name         = "listener-default"
    backend_address_pool_name  = "pool-bovipro-prod"
    backend_http_settings_name = "http-settings-bovipro"
  }
}

# ---------- Outputs -----------------------------------------------------------
output "public_ip_address" {
  value = azurerm_public_ip.appgw.ip_address
}

output "public_ip_id" {
  value = azurerm_public_ip.appgw.id
}

output "appgw_id" {
  value = azurerm_application_gateway.main.id
}

output "appgw_name" {
  value = azurerm_application_gateway.main.name
}
