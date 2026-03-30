output "environment" {
  description = "Configured environment name."
  value       = var.environment
}

output "resource_group_infra" {
  description = "Resource group containing network and private endpoints."
  value       = azurerm_resource_group.infra_rg.name
}

output "resource_group_apphosting" {
  description = "Resource group containing App Service and app storage."
  value       = azurerm_resource_group.apphosting_rg.name
}

output "resource_group_monitoring" {
  value = azurerm_resource_group.monitoring_rg.name
}

output "resource_group_security" {
  value = azurerm_resource_group.security_rg.name
}

output "virtual_network_id" {
  value = azurerm_virtual_network.infocomp_vnet.id
}

output "web_app_name" {
  value = azurerm_windows_web_app.infocomp_webapp.name
}

output "web_app_default_hostname" {
  value = azurerm_windows_web_app.infocomp_webapp.default_hostname
}

output "application_insights_connection_string" {
  description = "Use only in secure pipelines or Key Vault; do not log."
  value       = azurerm_application_insights.infocomp_ai.connection_string
  sensitive   = true
}

output "key_vault_id" {
  value = azurerm_key_vault.infocomp_kv.id
}

output "key_vault_uri" {
  value = azurerm_key_vault.infocomp_kv.vault_uri
}

output "storage_account_infocomp" {
  value = azurerm_storage_account.infocomp_storage.name
}

output "application_gateway_public_ip" {
  description = "Public IP of Application Gateway when app_gateway_config.enabled is true."
  value       = try(azurerm_public_ip.application_gateway[0].ip_address, null)
}

output "application_gateway_id" {
  description = "Resource ID of Application Gateway when enabled."
  value       = try(azurerm_application_gateway.main[0].id, null)
}

output "application_gateway_name" {
  description = "Name of Application Gateway when enabled."
  value       = try(azurerm_application_gateway.main[0].name, null)
}

output "github_runner_private_ip" {
  description = "Private IP of the self-hosted runner VM (VNet access to private Web App)."
  value       = length(azurerm_network_interface.github_runner) > 0 ? azurerm_network_interface.github_runner[0].private_ip_address : null
}

output "github_runner_public_ip" {
  description = "Public IP for SSH and GitHub egress when assign_public_ip is true."
  value       = length(azurerm_public_ip.github_runner) > 0 ? azurerm_public_ip.github_runner[0].ip_address : null
}

output "github_runner_ssh_hint" {
  description = "SSH command when runner has a public IP."
  value       = length(azurerm_public_ip.github_runner) > 0 ? "ssh ${var.github_runner.admin_username}@${azurerm_public_ip.github_runner[0].ip_address}" : null
}

