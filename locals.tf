##############################################################################
# Locals
##############################################################################

locals {
  tags = {
    project     = var.project_name
    environment = var.environment
    managed_by  = "terraform"
    repo        = "terraform-azurerm-openclaw"
  }

  ssh_public_key = var.ssh_public_key != "" ? var.ssh_public_key : tls_private_key.ssh[0].public_key_openssh

  # When Key Vault is enabled and an API key was provided, the VM fetches it
  # at boot via managed identity — do not embed the raw key in cloud-init.
  use_key_vault_secrets = var.enable_key_vault && (
    var.anthropic_api_key != "" || var.azure_openai_api_key != "" ||
    (var.enable_teams && var.ms_app_password != "")
  )

  key_vault_name = var.enable_key_vault ? azurerm_key_vault.openclaw[0].name : ""

  # Let's Encrypt is enabled when either public HTTPS or Teams requires a real cert
  enable_letsencrypt = (
    (var.enable_public_https && var.public_domain != "" && var.acme_email != "") ||
    (var.enable_teams && var.teams_bot_domain != "" && var.teams_acme_email != "")
  )

  # Pick the ACME email: public_domain takes priority, fall back to teams email
  acme_email_effective = var.acme_email != "" ? var.acme_email : var.teams_acme_email

  cloud_init = templatefile("${path.module}/cloud-init.yaml", {
    admin_username        = var.admin_username
    openclaw_version      = var.openclaw_version
    llm_provider          = var.llm_provider
    use_key_vault_secrets = local.use_key_vault_secrets
    key_vault_name        = local.key_vault_name
    # Raw keys only injected when Key Vault is disabled (fallback mode)
    anthropic_api_key     = local.use_key_vault_secrets ? "" : var.anthropic_api_key
    azure_openai_endpoint = var.azure_openai_endpoint
    azure_openai_api_key  = local.use_key_vault_secrets ? "" : var.azure_openai_api_key
    azure_openai_deployment = var.azure_openai_deployment
    enable_tailscale      = var.enable_tailscale
    tailscale_auth_key    = var.tailscale_auth_key
    project_name          = var.project_name
    # Public HTTPS
    enable_public_https  = var.enable_public_https
    public_domain        = var.public_domain
    enable_letsencrypt   = local.enable_letsencrypt
    acme_email_effective = local.acme_email_effective
    # Teams
    enable_teams     = var.enable_teams
    ms_app_id        = var.ms_app_id
    teams_bot_domain = var.teams_bot_domain
    teams_acme_email = var.teams_acme_email
  })
}
