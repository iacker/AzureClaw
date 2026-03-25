##############################################################################
# Outputs
##############################################################################

output "public_ip" {
  description = "VM public IP address"
  value       = azurerm_public_ip.openclaw.ip_address
}

output "ssh_command" {
  description = "SSH command to connect to the VM"
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.openclaw.ip_address}"
}

output "tunnel_command" {
  description = "SSH tunnel to access OpenClaw gateway locally (localhost:18789)"
  value       = "ssh -N -L 18789:127.0.0.1:18789 ${var.admin_username}@${azurerm_public_ip.openclaw.ip_address}"
}

output "gateway_url" {
  description = "OpenClaw gateway URL (available after running 'make tunnel')"
  value       = "http://localhost:18789"
}

output "resource_group_name" {
  description = "Name of the Azure resource group"
  value       = azurerm_resource_group.openclaw.name
}

output "key_vault_name" {
  description = "Key Vault name (secrets stored here, fetched by VM at boot)"
  value       = var.enable_key_vault ? azurerm_key_vault.openclaw[0].name : "disabled"
}

output "vm_identity_principal_id" {
  description = "VM managed identity principal ID (for additional RBAC assignments)"
  value       = azurerm_linux_virtual_machine.openclaw.identity[0].principal_id
}

output "teams_bot_endpoint" {
  description = "Bot Framework messaging endpoint (configure in Azure Bot resource)"
  value       = var.enable_teams ? "https://${var.teams_bot_domain}/api/messages" : "disabled"
}

output "teams_ms_app_id" {
  description = "Microsoft App ID for the Teams bot (needed for manifest.json)"
  value       = var.enable_teams ? var.ms_app_id : "disabled"
}

output "ssh_private_key" {
  description = "Auto-generated SSH private key PEM (only when ssh_public_key was left empty). Save with: make save-key"
  value       = var.ssh_public_key == "" ? tls_private_key.ssh[0].private_key_pem : null
  sensitive   = true
}
