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
    Optional Application Gateway (v2): multi-site TLS from PFX files, backend = App Service private endpoint.
    PFX paths are relative to the Terraform working directory. Set enabled = false to skip all AGW resources.
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
    ssl_certificates = optional(map(object({
      pfx_file = string
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
    error_message = "When app_gateway_config.enabled is true, define at least one site and one ssl_certificates map entry."
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

variable "app_gateway_ssl_certificate_passwords" {
  type        = map(string)
  sensitive   = true
  default     = {}
  description = "PFX password per ssl_certificates key. Prefer env: TF_VAR_app_gateway_ssl_certificate_passwords='{\"main\":\"...\"}' instead of tfvars."
}

variable "github_runner" {
  description = <<-EOT
    Self-hosted GitHub Actions runner VM on vm_network_subnet (reaches private Web App over the VNet).
    Outbound to GitHub requires assign_public_ip = true or a separate NAT gateway on the subnet.
    After apply: SSH in, download actions-runner from GitHub releases, run ./config.sh with a registration token.
  EOT
  type = object({
    vm_size          = optional(string, "Standard_B2s")
    admin_username   = optional(string, "azureuser")
    ssh_public_key   = string
    assign_public_ip = optional(bool, true)
    allow_ssh_cidrs  = optional(list(string), ["0.0.0.0/0"])
    disk_size_gb     = optional(number, 128)
    install_docker   = optional(bool, true)
  })

  validation {
    condition     = length(trimspace(var.github_runner.ssh_public_key)) > 0
    error_message = "github_runner.ssh_public_key must be set (e.g. in tfvars or TF_VAR_github_runner)."
  }
}
