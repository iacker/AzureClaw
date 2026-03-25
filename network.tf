##############################################################################
# Resource Group
##############################################################################

resource "azurerm_resource_group" "openclaw" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

##############################################################################
# Virtual Network & Subnet
##############################################################################

resource "azurerm_virtual_network" "openclaw" {
  name                = "vnet-${var.project_name}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.openclaw.location
  resource_group_name = azurerm_resource_group.openclaw.name
  tags                = local.tags
}

resource "azurerm_subnet" "openclaw" {
  name                 = "snet-${var.project_name}"
  resource_group_name  = azurerm_resource_group.openclaw.name
  virtual_network_name = azurerm_virtual_network.openclaw.name
  address_prefixes     = ["10.0.1.0/24"]
}

##############################################################################
# NSG — SSH only by default (gateway via SSH tunnel)
#
# Security posture:
#   - SSH restricted to ssh_allowed_cidrs (never 0.0.0.0/0)
#   - Gateway port 18789 only when expose_gateway = true (not recommended)
#   - Explicit DenyAll catch-all at priority 4096
##############################################################################

resource "azurerm_network_security_group" "openclaw" {
  name                = "nsg-${var.project_name}"
  location            = azurerm_resource_group.openclaw.location
  resource_group_name = azurerm_resource_group.openclaw.name
  tags                = local.tags

  security_rule {
    name                       = "AllowSSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = var.ssh_allowed_cidrs
    destination_address_prefix = "*"
  }

  dynamic "security_rule" {
    for_each = var.expose_gateway ? [1] : []
    content {
      name                       = "AllowGateway"
      priority                   = 110
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "18789"
      source_address_prefixes    = var.ssh_allowed_cidrs
      destination_address_prefix = "*"
    }
  }

  dynamic "security_rule" {
    for_each = (var.enable_teams || var.enable_public_https) ? [1] : []
    content {
      name                       = "AllowHTTP"
      priority                   = 120
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "80"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  }

  dynamic "security_rule" {
    for_each = (var.enable_teams || var.enable_public_https) ? [1] : []
    content {
      name                       = "AllowHTTPS"
      priority                   = 121
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  }

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "openclaw" {
  subnet_id                 = azurerm_subnet.openclaw.id
  network_security_group_id = azurerm_network_security_group.openclaw.id
}

##############################################################################
# Public IP
##############################################################################

resource "azurerm_public_ip" "openclaw" {
  name                = "pip-${var.project_name}"
  location            = azurerm_resource_group.openclaw.location
  resource_group_name = azurerm_resource_group.openclaw.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

##############################################################################
# Network Interface
##############################################################################

resource "azurerm_network_interface" "openclaw" {
  name                = "nic-${var.project_name}"
  location            = azurerm_resource_group.openclaw.location
  resource_group_name = azurerm_resource_group.openclaw.name
  tags                = local.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.openclaw.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.openclaw.id
  }
}
