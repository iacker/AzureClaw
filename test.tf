##############################################################################
# TEST VM — valide le nouveau cloud-init sans toucher la VM principale
#
# Usage:
#   terraform apply -target=azurerm_linux_virtual_machine.test \
#                   -target=azurerm_public_ip.test \
#                   -target=azurerm_network_interface.test
#
#   # Attendre ~5 min puis vérifier :
#   ssh -i ~/.ssh/openclaw.pem openclaw@$(terraform output -raw test_public_ip) \
#     'cloud-init status --long'
#
#   # Nettoyage :
#   terraform destroy -target=azurerm_linux_virtual_machine.test \
#                     -target=azurerm_public_ip.test \
#                     -target=azurerm_network_interface.test
#
# SUPPRIMER CE FICHIER après validation.
##############################################################################

resource "azurerm_public_ip" "test" {
  name                = "pip-openclaw-test"
  location            = azurerm_resource_group.openclaw.location
  resource_group_name = azurerm_resource_group.openclaw.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = merge(local.tags, { purpose = "cloud-init-test" })
}

resource "azurerm_network_interface" "test" {
  name                = "nic-openclaw-test"
  location            = azurerm_resource_group.openclaw.location
  resource_group_name = azurerm_resource_group.openclaw.name
  tags                = merge(local.tags, { purpose = "cloud-init-test" })

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.openclaw.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.test.id
  }
}

resource "azurerm_linux_virtual_machine" "test" {
  name                            = "vm-openclaw-test"
  location                        = azurerm_resource_group.openclaw.location
  resource_group_name             = azurerm_resource_group.openclaw.name
  size                            = "Standard_B2s" # moins cher pour un test
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.test.id]
  tags                            = merge(local.tags, { purpose = "cloud-init-test" })

  custom_data = base64encode(local.cloud_init)

  admin_ssh_key {
    username   = var.admin_username
    public_key = local.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS" # pas besoin de Premium pour un test
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }

  boot_diagnostics {}
}

# RBAC — la VM de test doit pouvoir lire le Key Vault
resource "azurerm_role_assignment" "test_kv_secrets_user" {
  count                = var.enable_key_vault ? 1 : 0
  scope                = azurerm_key_vault.openclaw[0].id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_virtual_machine.test.identity[0].principal_id
}

output "test_public_ip" {
  description = "IP de la VM de test (temporaire)"
  value       = azurerm_public_ip.test.ip_address
}

output "test_ssh_command" {
  description = "Commande SSH vers la VM de test"
  value       = "ssh -i ~/.ssh/openclaw.pem ${var.admin_username}@${azurerm_public_ip.test.ip_address}"
}
