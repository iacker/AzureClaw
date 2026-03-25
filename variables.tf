##############################################################################
# Variables
##############################################################################

variable "subscription_id" {
  description = "Azure subscription ID. Prefer ARM_SUBSCRIPTION_ID env var over hardcoding."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-openclaw"
}

variable "location" {
  description = "Azure region (westeurope = Netherlands, closest to Paris)"
  type        = string
  default     = "westeurope"

  validation {
    condition     = contains(["westeurope", "northeurope", "francecentral", "francesouth", "germanywestcentral", "eastus", "eastus2", "westus2", "westus3"], var.location)
    error_message = "Unsupported location. Use a valid Azure region slug (e.g. westeurope, francecentral)."
  }
}

variable "vm_size" {
  description = "VM size. Standard_B2ms (8 GB) recommended; Standard_B2s (4 GB) minimum."
  type        = string
  default     = "Standard_B2ms"

  validation {
    condition     = can(regex("^Standard_", var.vm_size))
    error_message = "vm_size must be a valid Azure VM size starting with 'Standard_'."
  }
}

variable "os_disk_size_gb" {
  description = "OS disk size in GB (minimum 30)"
  type        = number
  default     = 30

  validation {
    condition     = var.os_disk_size_gb >= 30
    error_message = "os_disk_size_gb must be at least 30 GB."
  }
}

variable "admin_username" {
  description = "SSH admin username"
  type        = string
  default     = "openclaw"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_-]{1,31}$", var.admin_username))
    error_message = "admin_username must be lowercase, start with a letter, and be 2-32 characters."
  }
}

variable "ssh_public_key" {
  description = "SSH public key content. Leave empty to auto-generate (save with: make save-key)."
  type        = string
  default     = ""
}

variable "ssh_allowed_cidrs" {
  description = "CIDRs allowed for SSH access. REQUIRED: restrict to your IP (e.g. [\"1.2.3.4/32\"])."
  type        = list(string)

  validation {
    condition     = length(var.ssh_allowed_cidrs) > 0
    error_message = "ssh_allowed_cidrs must not be empty. Use [\"YOUR_PUBLIC_IP/32\"] — never 0.0.0.0/0 in production."
  }
}

variable "expose_gateway" {
  description = "Expose OpenClaw gateway port 18789 publicly (false = SSH tunnel only, recommended)"
  type        = bool
  default     = false
}

variable "enable_key_vault" {
  description = "Create Azure Key Vault to store API keys. VM fetches secrets via managed identity at boot."
  type        = bool
  default     = true
}

variable "openclaw_version" {
  description = "OpenClaw git tag/branch to install (e.g. \"v1.2.0\"). Use \"latest\" for HEAD (not recommended in prod)."
  type        = string
  default     = "latest"
}

variable "llm_provider" {
  description = "LLM provider: anthropic, azure-openai, or openai"
  type        = string
  default     = "anthropic"

  validation {
    condition     = contains(["anthropic", "azure-openai", "openai"], var.llm_provider)
    error_message = "llm_provider must be one of: anthropic, azure-openai, openai."
  }
}

variable "anthropic_api_key" {
  description = "Anthropic API key. Stored in Key Vault when enable_key_vault = true."
  type        = string
  default     = ""
  sensitive   = true
}

variable "azure_openai_endpoint" {
  description = "Azure OpenAI endpoint URL (required when llm_provider = azure-openai)"
  type        = string
  default     = ""
}

variable "azure_openai_api_key" {
  description = "Azure OpenAI API key (required when llm_provider = azure-openai)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_tailscale" {
  description = "Install and configure Tailscale for zero-trust access (replaces public SSH exposure)"
  type        = bool
  default     = false
}

variable "tailscale_auth_key" {
  description = "Tailscale auth key (one-time or reusable, tskey-auth-...)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_teams" {
  description = "Enable Microsoft Teams integration via Azure Bot Framework and msteams plugin"
  type        = bool
  default     = false
}

variable "ms_app_id" {
  description = "Azure AD App Registration Client ID for the Teams bot (required when enable_teams = true)"
  type        = string
  default     = ""
}

variable "ms_app_password" {
  description = "Azure AD App Registration client secret for the Teams bot. Stored in Key Vault when enable_key_vault = true."
  type        = string
  default     = ""
  sensitive   = true
}

variable "teams_bot_domain" {
  description = "Public domain for the Teams HTTPS endpoint (e.g. openclaw.example.com). Must resolve to the VM IP. Required when enable_teams = true."
  type        = string
  default     = ""
}

variable "teams_acme_email" {
  description = "Email for Let's Encrypt certificate notifications. Required when enable_teams = true to get a valid TLS cert for the bot endpoint."
  type        = string
  default     = ""
}

variable "azure_openai_deployment" {
  description = "Azure OpenAI deployment name (required when llm_provider = azure-openai, e.g. my-gpt4-deployment)"
  type        = string
  default     = ""
}

variable "enable_public_https" {
  description = "Expose OpenClaw publicly over HTTPS with a real domain and Let's Encrypt TLS. Opens NSG ports 80/443."
  type        = bool
  default     = false
}

variable "public_domain" {
  description = "Public domain for OpenClaw HTTPS access (e.g. openclaw.example.com). Must resolve to the VM IP. Required when enable_public_https = true."
  type        = string
  default     = ""
}

variable "acme_email" {
  description = "Email for Let's Encrypt certificate notifications. Required when enable_public_https = true."
  type        = string
  default     = ""
}

variable "project_name" {
  description = "Project name used in resource naming and tags"
  type        = string
  default     = "openclaw"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,18}[a-z0-9]$", var.project_name))
    error_message = "project_name must be lowercase alphanumeric with hyphens, 3-20 characters."
  }
}

variable "environment" {
  description = "Environment tag"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}
