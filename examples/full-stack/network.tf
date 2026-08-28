# ╔══════════════════════════════════════════════════════════════════╗
# ║  OPTIONAL HUB NETWORK - created only with enable_private_link    ║
# ║                                                                  ║
# ║  ACI VNet injection needs a subnet delegated to                  ║
# ║  Microsoft.ContainerInstance/containerGroups, and the delegated  ║
# ║  subnet needs an NSG that lets Azure's own health probes in.     ║
# ╚══════════════════════════════════════════════════════════════════╝

resource "azurerm_virtual_network" "this" {
  count = var.enable_private_link ? 1 : 0

  name                = local.network_name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.virtual_network_address_space]

  tags = merge(local.standard_tags, { Service = "Network" })
}

# Subnet for ACI (delegated). Private IPs come from here.
resource "azurerm_subnet" "aci" {
  count = var.enable_private_link ? 1 : 0

  name                 = "snet-aci"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this[0].name
  address_prefixes     = [var.aci_subnet_prefix]

  service_endpoints = ["Microsoft.ContainerRegistry"]

  delegation {
    name = "aci-delegation"

    service_delegation {
      name    = "Microsoft.ContainerInstance/containerGroups"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# Subnet for the registry private endpoint (separate so NSG rules for ACI do
# not accidentally block the private link NIC).
resource "azurerm_subnet" "private_endpoints" {
  count = var.enable_private_link ? 1 : 0

  name                 = "snet-pe"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this[0].name
  address_prefixes     = [var.private_endpoint_subnet_prefix]
}

resource "azurerm_network_security_group" "aci" {
  count = var.enable_private_link ? 1 : 0

  name                = "nsg-${local.network_name}-aci"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name

  # Required by Azure for ACI in a VNet: the platform probes the pods from the
  # AzureLoadBalancer address prefix, and app traffic arrives from the VNet.
  security_rule {
    name                       = "allow-vnet-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = "VirtualNetwork"
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "*"
  }

  security_rule {
    name                       = "allow-azure-loadbalancer-probes"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = "AzureLoadBalancer"
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "60000-65535"
  }

  tags = merge(local.standard_tags, { Service = "Network" })
}

resource "azurerm_subnet_network_security_group_association" "aci" {
  count = var.enable_private_link ? 1 : 0

  subnet_id                 = azurerm_subnet.aci[0].id
  network_security_group_id = azurerm_network_security_group.aci[0].id

  depends_on = [azurerm_subnet.aci]
}

# ─── PRIVATE DNS FOR THE REGISTRY PRIVATE ENDPOINT ────────────────
resource "azurerm_private_dns_zone" "registry" {
  count = var.enable_private_link ? 1 : 0

  name                = "privatelink.azurecr.io"
  resource_group_name = azurerm_resource_group.this.name

  tags = merge(local.standard_tags, { Service = "ContainerRegistry" })
}

resource "azurerm_private_dns_zone_virtual_network_link" "registry" {
  count = var.enable_private_link ? 1 : 0

  name                  = "link-${local.network_name}-azurecr"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.registry[0].name
  virtual_network_id    = azurerm_virtual_network.this[0].id
  registration_enabled  = false

  tags = merge(local.standard_tags, { Service = "ContainerRegistry" })
}
