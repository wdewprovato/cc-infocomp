data "azurerm_client_config" "current" {}

moved {
  from = azurerm_app_service_plan.infocomp_plan
  to   = azurerm_service_plan.infocomp_plan
}

// Storage account names: 3–24 chars, lowercase letters and numbers only (no hyphens).
locals {
  env_lower = lower(var.environment)
  env_no_sep = replace(
    replace(replace(replace(local.env_lower, "-", ""), "_", ""), ".", ""),
    " ", ""
  )
  env_slug_alnum        = substr(local.env_no_sep, 0, 14)
  tf_state_storage_name = "tfstatedeveus"
  infocomp_storage_name = substr("stccinfocomp${local.env_slug_alnum}", 0, 24)
}

// Resource group for infrastructure, environment included in the name dynamically
resource "azurerm_resource_group" "infra_rg" {
  name     = "rg-cc-infocomp-${var.environment}-infra-eus-01"
  location = var.location
}

// Resource group for application hosting
resource "azurerm_resource_group" "apphosting_rg" {
  name     = "rg-cc-infocomp-${var.environment}-apphosting-eus-01"
  location = var.location
}

// Resource group for monitoring
resource "azurerm_resource_group" "monitoring_rg" {
  name     = "rg-cc-infocomp-${var.environment}-monitoring-eus-01"
  location = var.location
}

// Resource group for security
resource "azurerm_resource_group" "security_rg" {
  name     = "rg-cc-infocomp-${var.environment}-security-eus-01"
  location = var.location
}

// Resource group for state management
resource "azurerm_resource_group" "state_rg" {
  name     = "rg-cc-infocomp-${var.environment}-state-eus-01"
  location = var.location
}

// Virtual Network
resource "azurerm_virtual_network" "infocomp_vnet" {
  name                = "vnet-cc-infocomp-${var.environment}"
  resource_group_name = azurerm_resource_group.infra_rg.name
  location            = azurerm_resource_group.infra_rg.location
  address_space       = ["10.36.0.0/16"]
}

// Subnet for Private Endpoint Connections
resource "azurerm_subnet" "pec_subnet" {
  name                              = "pec-cc-subnet-${var.environment}"
  resource_group_name               = azurerm_resource_group.infra_rg.name
  virtual_network_name              = azurerm_virtual_network.infocomp_vnet.name
  address_prefixes                  = ["10.36.1.0/24"]
  private_endpoint_network_policies = "Enabled"
}

// Subnet for VNet Integration
resource "azurerm_subnet" "vnet_integration_subnet" {
  name                 = "vnet-integration-subnet-${var.environment}"
  resource_group_name  = azurerm_resource_group.infra_rg.name
  virtual_network_name = azurerm_virtual_network.infocomp_vnet.name
  address_prefixes     = ["10.36.2.0/24"]
  service_endpoints    = ["Microsoft.Web"]
}

// Subnet for VM Network
resource "azurerm_subnet" "vm_network_subnet" {
  name                 = "vm-network-subnet-${var.environment}"
  resource_group_name  = azurerm_resource_group.infra_rg.name
  virtual_network_name = azurerm_virtual_network.infocomp_vnet.name
  address_prefixes     = ["10.36.3.0/24"]
}

// Storage Account for App Hosting Resources
resource "azurerm_storage_account" "infocomp_storage" {
  name                     = local.infocomp_storage_name
  resource_group_name      = azurerm_resource_group.apphosting_rg.name
  location                 = azurerm_resource_group.apphosting_rg.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "GRS"

  allow_nested_items_to_be_public = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_table" "infocomp_table" {
  name                 = "ccinfocomptable"
  storage_account_name = azurerm_storage_account.infocomp_storage.name
}

// App Service Plan
resource "azurerm_service_plan" "infocomp_plan" {
  name                = "asp-cc-infocomp-${var.environment}"
  location            = azurerm_resource_group.apphosting_rg.location
  resource_group_name = azurerm_resource_group.apphosting_rg.name
  os_type             = "Windows"
  sku_name            = "S1"
}

// Web App
resource "azurerm_windows_web_app" "infocomp_webapp" {
  name                = "webapp-cc-infocomp-${var.environment}"
  location            = azurerm_resource_group.apphosting_rg.location
  resource_group_name = azurerm_resource_group.apphosting_rg.name
  service_plan_id     = azurerm_service_plan.infocomp_plan.id

  identity {
    type = "SystemAssigned"
  }

  site_config {}

  app_settings = {
    APPLICATIONINSIGHTS_CONNECTION_STRING      = azurerm_application_insights.infocomp_ai.connection_string
    APPINSIGHTS_INSTRUMENTATIONKEY             = azurerm_application_insights.infocomp_ai.instrumentation_key
    ApplicationInsightsAgent_EXTENSION_VERSION = "~3"
  }

  depends_on = [
    azurerm_storage_account.infocomp_storage
  ]
}

// Private Endpoint for Web App
resource "azurerm_private_endpoint" "webapp_endpoint" {
  name                = "webapp-cc-infocomp-pe-${var.environment}"
  resource_group_name = azurerm_resource_group.infra_rg.name
  location            = azurerm_resource_group.infra_rg.location
  subnet_id           = azurerm_subnet.pec_subnet.id

  private_service_connection {
    name                           = "webapp-cc-infocompprivate-service-${var.environment}"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_windows_web_app.infocomp_webapp.id
    subresource_names              = ["sites"]
  }
}

// Application Insights
resource "azurerm_application_insights" "infocomp_ai" {
  name                = "appinsights-cc-infocomp-${var.environment}"
  location            = azurerm_resource_group.monitoring_rg.location
  resource_group_name = azurerm_resource_group.monitoring_rg.name
  application_type    = "web"
}

// Key Vault
resource "azurerm_key_vault" "infocomp_kv" {
  name                = "kv-cc-infocomp-${var.environment}"
  resource_group_name = azurerm_resource_group.security_rg.name
  location            = azurerm_resource_group.security_rg.location

  sku_name = "standard"

  tenant_id = data.azurerm_client_config.current.tenant_id

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = azurerm_windows_web_app.infocomp_webapp.identity[0].principal_id

    secret_permissions = ["Get", "List"]
  }
}

// Private Endpoint for Key Vault
resource "azurerm_private_endpoint" "keyvault_endpoint" {
  name                = "kv-cc-infocomp-pe-${var.environment}"
  resource_group_name = azurerm_resource_group.infra_rg.name
  location            = azurerm_resource_group.infra_rg.location
  subnet_id           = azurerm_subnet.pec_subnet.id

  private_service_connection {
    name                           = "keyvault-cc-private-service-${var.environment}"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_key_vault.infocomp_kv.id
    subresource_names              = ["vault"]
  }
}

// Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "infocomp_law" {
  name                = "law-cc-infocomp-${var.environment}"
  location            = azurerm_resource_group.monitoring_rg.location
  resource_group_name = azurerm_resource_group.monitoring_rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}
