##############################################################################
# SSH Key (auto-generated when ssh_public_key is not provided)
##############################################################################

resource "tls_private_key" "ssh" {
  count     = var.ssh_public_key == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

##############################################################################
# Virtual Machine
#
# Security posture:
#   - Password authentication disabled
#   - SSH key-only access
#   - SystemAssigned managed identity (no stored credentials)
#   - Boot diagnostics enabled (serial console + screenshot for debugging)
#   - prevent_destroy guard — Terraform cannot destroy this resource
#   - cloud-init only runs on first boot (ignore_changes on custom_data)
##############################################################################

resource "azurerm_linux_virtual_machine" "openclaw" {
  name                = "vm-${var.project_name}"
  location            = azurerm_resource_group.openclaw.location
  resource_group_name = azurerm_resource_group.openclaw.name
  size                = var.vm_size
  admin_username      = var.admin_username

  network_interface_ids = [azurerm_network_interface.openclaw.id]

  admin_ssh_key {
    username   = var.admin_username
    public_key = local.ssh_public_key
  }

  disable_password_authentication = true

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  custom_data = base64encode(local.cloud_init)

  identity {
    type = "SystemAssigned"
  }

  # Boot diagnostics — uses Azure-managed storage (no storage account resource needed).
  # Enables serial console access and VM screenshot capture for debugging boot failures.
  boot_diagnostics {}

  tags = local.tags

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [custom_data] # cloud-init runs only on first boot
  }
}

##############################################################################
# RBAC — VM managed identity → Key Vault Secrets User (read-only at runtime)
##############################################################################

resource "azurerm_role_assignment" "kv_vm" {
  count                = var.enable_key_vault ? 1 : 0
  scope                = azurerm_key_vault.openclaw[0].id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_virtual_machine.openclaw.identity[0].principal_id
}
