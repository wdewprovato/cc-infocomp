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

// Resource group for github runner
resource "azurerm_resource_group" "cicd_rg" {
  name     = "rg-cc-infocomp-${var.environment}-cicd-eus-01"
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
    prevent_destroy = false
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

// -----------------------------------------------------------------------------
// GitHub self-hosted Actions runner (Linux) on vm_network_subnet — private VNet
// access to Web App PE; public IP optional for GitHub / package egress.
// -----------------------------------------------------------------------------

resource "azurerm_network_security_group" "github_runner" {
  name                = "nsg-cc-infocomp-github-runner-${var.environment}"
  location            = azurerm_resource_group.cicd_rg.location
  resource_group_name = azurerm_resource_group.cicd_rg.name
}


resource "azurerm_network_security_rule" "github_runner_ssh" {
  name                        = "AllowSSH"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefixes     = var.github_runner.allow_ssh_cidrs
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.cicd_rg.name
  network_security_group_name = azurerm_network_security_group.github_runner[0].name
}

resource "azurerm_public_ip" "github_runner" {
  name                = "pip-cc-infocomp-github-runner-${var.environment}"
  location            = azurerm_resource_group.cicd_rg.location
  resource_group_name = azurerm_resource_group.cicd_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "github_runner" {
  name                = "nic-cc-infocomp-github-runner-${var.environment}"
  location            = azurerm_resource_group.cicd_rg.location
  resource_group_name = azurerm_resource_group.cicd_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vm_network_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.github_runner.assign_public_ip ? azurerm_public_ip.github_runner[0].id : null
  }
}

resource "azurerm_network_interface_security_group_association" "github_runner" {
  network_interface_id      = azurerm_network_interface.github_runner[0].id
  network_security_group_id = azurerm_network_security_group.github_runner[0].id
}

locals {
  github_runner_cloud_init = var.github_runner.enabled ? base64encode(join("", [
    "#cloud-config\n",
    yamlencode({
      package_update  = true
      package_upgrade = false
      packages = concat(
        ["ca-certificates", "curl", "git", "jq", "unzip"],
        var.github_runner.install_docker ? ["docker.io"] : []
      )
      runcmd = concat(
        var.github_runner.install_docker ? [
          ["systemctl", "enable", "docker"],
          ["systemctl", "start", "docker"],
          ["usermod", "-aG", "docker", var.github_runner.admin_username],
        ] : [],
        [["sh", "-c", "echo 'GitHub Actions runner: install from https://github.com/actions/runner then ./config.sh' >> /etc/motd"]]
      )
    }),
  ])) : ""
}

resource "azurerm_linux_virtual_machine" "github_runner" {
  name                = "vm-cc-infocomp-github-runner-${var.environment}"
  location            = azurerm_resource_group.cicd_rg.location
  resource_group_name = azurerm_resource_group.cicd_rg.name
  size                = var.github_runner.vm_size
  admin_username      = var.github_runner.admin_username
  custom_data         = local.github_runner_cloud_init

  network_interface_ids = [
    azurerm_network_interface.github_runner[0].id,
  ]

  admin_ssh_key {
    username   = var.github_runner.admin_username
    public_key = var.github_runner.ssh_public_key
  }

  os_disk {
    name                 = "osdisk-github-runner-${var.environment}"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.github_runner.disk_size_gb
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }

  depends_on = [
    azurerm_network_interface_security_group_association.github_runner,
  ]
}
