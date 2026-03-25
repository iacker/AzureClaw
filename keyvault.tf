##############################################################################
# Random suffix — Key Vault name must be globally unique & start with a letter
##############################################################################

resource "random_string" "suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = false
  special = false
}

##############################################################################
# Key Vault
#
# Security posture:
#   - RBAC authorization only (no legacy access policies)
#   - Soft-delete 30 days + purge protection — prevents accidental key loss
#   - prevent_destroy guard — Terraform cannot destroy this resource
#   - Deployer gets Secrets Officer (write) only during terraform apply
#   - VM gets Secrets User (read-only) at runtime via managed identity
##############################################################################

resource "azurerm_key_vault" "openclaw" {
  count = var.enable_key_vault ? 1 : 0

  name                       = "kv-${var.project_name}-${random_string.suffix.result}"
  location                   = azurerm_resource_group.openclaw.location
  resource_group_name        = azurerm_resource_group.openclaw.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 30
  purge_protection_enabled   = true
  rbac_authorization_enabled = true
  tags                       = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

# Deployer identity — needs Secrets Officer to write secrets via Terraform
resource "azurerm_role_assignment" "kv_deployer" {
  count                = var.enable_key_vault ? 1 : 0
  scope                = azurerm_key_vault.openclaw[0].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Store API keys in Key Vault — VM fetches them at boot via managed identity
resource "azurerm_key_vault_secret" "anthropic_api_key" {
  count        = var.enable_key_vault && var.anthropic_api_key != "" ? 1 : 0
  name         = "anthropic-api-key"
  value        = var.anthropic_api_key
  key_vault_id = azurerm_key_vault.openclaw[0].id

  depends_on = [azurerm_role_assignment.kv_deployer]
}

resource "azurerm_key_vault_secret" "azure_openai_api_key" {
  count        = var.enable_key_vault && var.azure_openai_api_key != "" ? 1 : 0
  name         = "azure-openai-api-key"
  value        = var.azure_openai_api_key
  key_vault_id = azurerm_key_vault.openclaw[0].id

  depends_on = [azurerm_role_assignment.kv_deployer]
}
