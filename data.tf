##############################################################################
# Data sources
##############################################################################

# Current Azure client — used for Key Vault tenant_id and deployer principal_id
data "azurerm_client_config" "current" {}
