##############################################################################
# Teams Integration — Azure Bot Service
#
# Prerequisites before setting enable_teams = true:
#   1. Create an Azure AD App Registration (portal.azure.com → App registrations)
#      → Note the Application (client) ID → set as ms_app_id
#      → Create a client secret → set as ms_app_password
#   2. Point a domain at the VM public IP → set as teams_bot_domain
#      (Let's Encrypt TLS provisioned by Traefik when teams_acme_email is set)
#
# After apply:
#   make teams-manifest   → generate Teams app package (upload to Teams Admin)
##############################################################################

resource "azurerm_bot_service_azure_bot" "openclaw" {
  count = var.enable_teams ? 1 : 0

  name                = "bot-${var.project_name}"
  resource_group_name = azurerm_resource_group.openclaw.name
  location            = "global"
  sku                 = "F0" # Free tier — upgrade to S1 if >10k messages/month

  microsoft_app_id   = var.ms_app_id
  microsoft_app_type = "MultiTenant"

  endpoint = "https://${var.teams_bot_domain}/api/messages"

  tags = local.tags
}

resource "azurerm_bot_channel_ms_teams" "openclaw" {
  count = var.enable_teams ? 1 : 0

  bot_name            = azurerm_bot_service_azure_bot.openclaw[0].name
  location            = azurerm_bot_service_azure_bot.openclaw[0].location
  resource_group_name = azurerm_resource_group.openclaw.name
}

# Store Teams bot client secret in Key Vault
resource "azurerm_key_vault_secret" "ms_app_password" {
  count        = var.enable_teams && var.enable_key_vault && var.ms_app_password != "" ? 1 : 0
  name         = "ms-app-password"
  value        = var.ms_app_password
  key_vault_id = azurerm_key_vault.openclaw[0].id

  depends_on = [azurerm_role_assignment.kv_deployer]
}
