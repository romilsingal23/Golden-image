
data "azurerm_resource_group" "build_network" {
  count    = local.is_local ? 1 : 0
  name     = "cdtk_golden_image_azu_build" 
}

data "azurerm_virtual_network" "build_network" {
  count               = local.is_local ? 1 : 0
  name                = "cdtk_golden_image_azu_build"
  resource_group_name = "cdtk_golden_image_azu_build"
}

resource "azurerm_virtual_network" "build_network" {
  count               = local.is_local ? 0 : 1
  name                = local.build_name
  location            = var.azu_location
  resource_group_name = local.resource_group_name
  address_space       = local.vnet_range
  tags                = var.tags
}

resource "azurerm_resource_group" "build_network" {
  count    = local.is_local ? 0 : 1
  name     = local.build_name
  location = var.azu_location
  tags     = var.tags
}


locals {
  resource_group_location   = local.is_local ? data.azurerm_resource_group.build_network[0].location : azurerm_resource_group.build_network[0].location
  resource_group_name       = local.is_local ? data.azurerm_resource_group.build_network[0].name : azurerm_resource_group.build_network[0].name
  virtual_network_name      = local.is_local ? data.azurerm_virtual_network.build_network[0].name : azurerm_virtual_network.build_network[0].name
  resource_group_id         = local.is_local ? data.azurerm_resource_group.build_network[0].id : azurerm_resource_group.build_network[0].id
}
resource "azurerm_subnet" "build_network" {
  for_each = {
    "${local.build_name}" : local.subnet_range
  }
  name                 = each.key
  address_prefixes     = each.value
  resource_group_name  = local.resource_group_name
  virtual_network_name = local.virtual_network_name
}

resource "azurerm_network_security_group" "build_network" {
  name                = local.build_name
  location            = var.azu_location
  resource_group_name = local.resource_group_name
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "build_network" {
  subnet_id                 = azurerm_subnet.build_network["${local.build_name}"].id
  network_security_group_id = azurerm_network_security_group.build_network.id
}
