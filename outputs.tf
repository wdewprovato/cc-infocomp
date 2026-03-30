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

output "terraform_state_storage_account" {
  description = "Storage account used for Terraform state (same module creates it)."
  value       = azurerm_storage_account.tf_state.name
}

output "terraform_state_container" {
  value = azurerm_storage_container.tf_state_container.name
}
