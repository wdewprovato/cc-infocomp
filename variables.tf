#-------------------------------------------------------------------------------
# Terraform Variables 
#-------------------------------------------------------------------------------

variable "environment" {
  description = "Deployment environment segment used in Azure resource names (e.g. dev, staging)."
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Azure region for all resources in this configuration."
  type        = string
  default     = "East US"
}

variable "app_gateway_config" {
  description = <<-EOT
    Optional Application Gateway (v2): TLS certificates from Azure Key Vault (PFX stored as secrets), backend = App Service private endpoint.
    Set enabled = false to skip all AGW resources. Upload each PFX to Key Vault as a secret (Base64 PKCS#12); reference by secret_name.
    Defaults to module Key Vault (azurerm_key_vault.infocomp_kv); set key_vault_id to use another vault.
    For WAF_v2, either enable_waf_configuration (inline OWASP) or set firewall_policy_id to a managed WAF policy.
    Standard_v2: set sku_name/sku_tier to Standard_v2 and enable_waf_configuration = false.
  EOT
  type = object({
    enabled                      = bool
    sku_name                     = optional(string, "WAF_v2")
    sku_tier                     = optional(string, "WAF_v2")
    capacity                     = optional(number, 2)
    subnet_address_prefixes      = optional(list(string), ["10.36.4.0/26"])
    zones                        = optional(list(string), [])
    ssl_policy_name              = optional(string, "AppGwSslPolicy20220101")
    redirect_http_to_https       = optional(bool, true)
    enable_waf_configuration     = optional(bool, true)
    waf_firewall_mode            = optional(string, "Prevention")
    waf_rule_set_version         = optional(string, "3.2")
    waf_file_upload_limit_mb     = optional(number, 100)
    waf_max_request_body_size_kb = optional(number, 128)
    firewall_policy_id           = optional(string, null)
    key_vault_id                 = optional(string, null)
    ssl_certificates = optional(map(object({
      secret_name = string
    })), {})
    sites = optional(list(object({
      name                = string
      host_name           = string
      ssl_certificate_key = string
      backend_host_header = optional(string)
      health_probe_path   = optional(string, "/")
    })), [])
  })
  default = {
    enabled = false
    sites   = []
  }

  validation {
    condition = !var.app_gateway_config.enabled || (
      length(var.app_gateway_config.sites) > 0 &&
      length(var.app_gateway_config.ssl_certificates) > 0
    )
    error_message = "When app_gateway_config.enabled is true, define at least one site and one ssl_certificates entry (Key Vault secret names)."
  }

  validation {
    condition = !var.app_gateway_config.enabled || alltrue([
      for s in var.app_gateway_config.sites :
      contains(keys(var.app_gateway_config.ssl_certificates), s.ssl_certificate_key)
    ])
    error_message = "Each site.ssl_certificate_key must match a key in ssl_certificates."
  }

  validation {
    condition = !var.app_gateway_config.enabled || (
      var.app_gateway_config.capacity >= 1 && var.app_gateway_config.capacity <= 125
    )
    error_message = "Application Gateway capacity must be between 1 and 125."
  }

  validation {
    condition = !var.app_gateway_config.enabled || !strcontains(var.app_gateway_config.sku_tier, "WAF") || (
      var.app_gateway_config.enable_waf_configuration || try(var.app_gateway_config.firewall_policy_id, null) != null
    )
    error_message = "WAF tier requires enable_waf_configuration or a non-null firewall_policy_id."
  }

  validation {
    condition = !var.app_gateway_config.enabled || (
      try(var.app_gateway_config.firewall_policy_id, null) == null || !var.app_gateway_config.enable_waf_configuration
    )
    error_message = "Use either firewall_policy_id or enable_waf_configuration, not both."
  }
}

variable "github_runner" {
  description = <<-EOT
    Self-hosted GitHub Actions runner VM on vm_network_subnet (reaches private Web App over the VNet).
    Outbound to GitHub requires assign_public_ip = true or a separate NAT gateway on the subnet.
    SSH: an RSA keypair is created by Terraform (tls_private_key); retrieve the private key with
    terraform output -raw github_runner_ssh_private_key_openssh (sensitive; also stored in remote state).
    After apply: SSH in, install actions/runner, run ./config.sh with a registration token.
  EOT
  type = object({
    vm_size          = optional(string, "Standard_B2s")
    admin_username   = optional(string, "azureuser")
    assign_public_ip = optional(bool, true)
    allow_ssh_cidrs  = optional(list(string), ["0.0.0.0/0"])
    disk_size_gb     = optional(number, 128)
    install_docker   = optional(bool, true)
  })
  default = {}
}
