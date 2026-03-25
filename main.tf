##############################################################################
# terraform-azurerm-openclaw
# Deploy OpenClaw on Azure VM with Docker, cloud-init, and Key Vault secrets
#
# Resources are split by concern — read the relevant file directly:
#
#   versions.tf  — Terraform + provider requirements & remote backend config
#   data.tf      — Data sources (current Azure client config)
#   network.tf   — Resource group, VNet, subnet, NSG, public IP, NIC
#   keyvault.tf  — Key Vault, secrets, RBAC for deployer identity
#   compute.tf   — SSH key, VM (with boot diagnostics), RBAC for VM identity
#   locals.tf    — Local values: tags, SSH key selection, cloud-init template
#   variables.tf — All input variables with descriptions and validations
#   outputs.tf   — SSH command, tunnel command, gateway URL, key vault name
##############################################################################
