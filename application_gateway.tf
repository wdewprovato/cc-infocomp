#-------------------------------------------------------------------------------
# Terraform - Application Gateway 

# Application Gateway: TLS certs from Key Vault secrets (PFX as Base64),
# user-assigned identity + Key Vault access policy, multi-site listeners,
# HTTP→HTTPS redirect, backend = App Service via private endpoint IP.
# See config/app-gateway.auto.tfvars.example.
# -----------------------------------------------------------------------------


# NIC for the Web App private endpoint (provider 4.x exposes IP via the linked interface).
data "azurerm_network_interface" "webapp_private_endpoint" {
  count = var.app_gateway_config.enabled ? 1 : 0

  name                = azurerm_private_endpoint.webapp_endpoint.network_interface[0].name
  resource_group_name = azurerm_resource_group.security_rg.name
}

locals {
  app_gateway_key_vault_id = coalesce(var.app_gateway_config.key_vault_id, azurerm_key_vault.infocomp_kv.id)

  agw_sites_map = var.app_gateway_config.enabled ? {
    for s in var.app_gateway_config.sites : s.name => s
  } : {}

  agw_site_priority_index = {
    for i, n in sort(keys(local.agw_sites_map)) : n => i
  }

  agw_backend_host = {
    for k, s in local.agw_sites_map : k => coalesce(
      try(s.backend_host_header, null),
      azurerm_windows_web_app.infocomp_webapp.default_hostname
    )
  }

  agw_waf_inline = var.app_gateway_config.enable_waf_configuration && strcontains(var.app_gateway_config.sku_tier, "WAF")
}

data "azurerm_key_vault_secret" "app_gateway_ssl" {
  for_each = var.app_gateway_config.enabled ? var.app_gateway_config.ssl_certificates : {}

  name         = each.value.secret_name
  key_vault_id = local.app_gateway_key_vault_id
}

resource "azurerm_user_assigned_identity" "app_gateway" {
  count = var.app_gateway_config.enabled ? 1 : 0

  name                = "uami-cc-infocomp-appgw-${var.environment}"
  location            = azurerm_resource_group.infra_rg.location
  resource_group_name = azurerm_resource_group.infra_rg.name
}

resource "azurerm_key_vault_access_policy" "app_gateway" {
  count = var.app_gateway_config.enabled ? 1 : 0

  key_vault_id = local.app_gateway_key_vault_id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.app_gateway[0].principal_id

  secret_permissions = ["Get"]
}

# Dedicated subnet (Application Gateway must be alone in its subnet; /26+ for v2).
resource "azurerm_subnet" "application_gateway" {
  count = var.app_gateway_config.enabled ? 1 : 0

  name                 = "snet-cc-infocomp-agw-${var.environment}"
  resource_group_name  = azurerm_resource_group.infra_rg.name
  virtual_network_name = azurerm_virtual_network.infocomp_vnet.name
  address_prefixes     = var.app_gateway_config.subnet_address_prefixes
}

resource "azurerm_public_ip" "application_gateway" {
  count = var.app_gateway_config.enabled ? 1 : 0

  name                = "pip-cc-infocomp-agw-${var.environment}"
  location            = azurerm_resource_group.infra_rg.location
  resource_group_name = azurerm_resource_group.infra_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = length(var.app_gateway_config.zones) > 0 ? var.app_gateway_config.zones : null
}

resource "azurerm_application_gateway" "main" {
  count = var.app_gateway_config.enabled ? 1 : 0

  name                = "agw-cc-infocomp-${var.environment}"
  resource_group_name = azurerm_resource_group.infra_rg.name
  location            = azurerm_resource_group.infra_rg.location

  sku {
    name     = var.app_gateway_config.sku_name
    tier     = var.app_gateway_config.sku_tier
    capacity = var.app_gateway_config.capacity
  }

  zones = length(var.app_gateway_config.zones) > 0 ? var.app_gateway_config.zones : null

  dynamic "waf_configuration" {
    for_each = local.agw_waf_inline ? [1] : []
    content {
      enabled                  = true
      firewall_mode            = var.app_gateway_config.waf_firewall_mode
      rule_set_type            = "OWASP"
      rule_set_version         = var.app_gateway_config.waf_rule_set_version
      file_upload_limit_mb     = var.app_gateway_config.waf_file_upload_limit_mb
      request_body_check       = true
      max_request_body_size_kb = var.app_gateway_config.waf_max_request_body_size_kb
    }
  }

  firewall_policy_id = var.app_gateway_config.firewall_policy_id

  ssl_policy {
    policy_type = "Predefined"
    policy_name = var.app_gateway_config.ssl_policy_name
  }

  gateway_ip_configuration {
    name      = "agw-ipcfg-${var.environment}"
    subnet_id = azurerm_subnet.application_gateway[0].id
  }

  frontend_port {
    name = "port-http"
    port = 80
  }

  frontend_port {
    name = "port-https"
    port = 443
  }

  frontend_ip_configuration {
    name                 = "feip-public"
    public_ip_address_id = azurerm_public_ip.application_gateway[0].id
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app_gateway[0].id]
  }

  dynamic "ssl_certificate" {
    for_each = var.app_gateway_config.ssl_certificates
    content {
      name                = ssl_certificate.key
      key_vault_secret_id = data.azurerm_key_vault_secret.app_gateway_ssl[ssl_certificate.key].id
    }
  }

  backend_address_pool {
    name         = "pool-app-${var.environment}"
    ip_addresses = [data.azurerm_network_interface.webapp_private_endpoint[0].private_ip_address]
  }

  dynamic "probe" {
    for_each = local.agw_sites_map
    content {
      name                                      = "probe-${probe.key}"
      protocol                                  = "Https"
      path                                      = coalesce(try(probe.value.health_probe_path, null), "/")
      host                                      = local.agw_backend_host[probe.key]
      interval                                  = 30
      timeout                                   = 30
      unhealthy_threshold                       = 3
      pick_host_name_from_backend_http_settings = false
      match {
        status_code = ["200-399"]
      }
    }
  }

  dynamic "backend_http_settings" {
    for_each = local.agw_sites_map
    content {
      name                                = "bhs-${backend_http_settings.key}"
      cookie_based_affinity               = "Disabled"
      port                                = 443
      protocol                            = "Https"
      request_timeout                     = 60
      probe_name                          = "probe-${backend_http_settings.key}"
      host_name                           = local.agw_backend_host[backend_http_settings.key]
      pick_host_name_from_backend_address = false
    }
  }

  dynamic "http_listener" {
    for_each = local.agw_sites_map
    content {
      name                           = "listener-https-${http_listener.key}"
      frontend_ip_configuration_name = "feip-public"
      frontend_port_name             = "port-https"
      protocol                       = "Https"
      host_name                      = http_listener.value.host_name
      ssl_certificate_name           = http_listener.value.ssl_certificate_key
      require_sni                    = true
    }
  }

  dynamic "http_listener" {
    for_each = var.app_gateway_config.redirect_http_to_https ? local.agw_sites_map : {}
    content {
      name                           = "listener-http-${http_listener.key}"
      frontend_ip_configuration_name = "feip-public"
      frontend_port_name             = "port-http"
      protocol                       = "Http"
      host_name                      = http_listener.value.host_name
    }
  }

  dynamic "redirect_configuration" {
    for_each = var.app_gateway_config.redirect_http_to_https ? local.agw_sites_map : {}
    content {
      name                 = "redirect-https-${redirect_configuration.key}"
      redirect_type        = "Permanent"
      target_listener_name = "listener-https-${redirect_configuration.key}"
      include_path         = true
      include_query_string = true
    }
  }

  dynamic "request_routing_rule" {
    for_each = var.app_gateway_config.redirect_http_to_https ? local.agw_site_priority_index : {}
    content {
      name                        = "rule-http-${request_routing_rule.key}"
      rule_type                   = "Basic"
      priority                    = 100 + request_routing_rule.value
      http_listener_name          = "listener-http-${request_routing_rule.key}"
      redirect_configuration_name = "redirect-https-${request_routing_rule.key}"
    }
  }

  dynamic "request_routing_rule" {
    for_each = local.agw_site_priority_index
    content {
      name                       = "rule-https-${request_routing_rule.key}"
      rule_type                  = "Basic"
      priority                   = 500 + request_routing_rule.value
      http_listener_name         = "listener-https-${request_routing_rule.key}"
      backend_address_pool_name  = "pool-app-${var.environment}"
      backend_http_settings_name = "bhs-${request_routing_rule.key}"
    }
  }

  depends_on = [
    azurerm_key_vault_access_policy.app_gateway,
    azurerm_private_endpoint.webapp_endpoint,
    azurerm_windows_web_app.infocomp_webapp,
  ]
}
