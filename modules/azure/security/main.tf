terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
  }
}

variable "name_prefix" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "subnet_ids" {
  type = map(string)
}

variable "security_groups" {
  type = map(map(object({
    priority    = number
    access      = string
    protocol    = string
    source      = string
    destination = string
  })))
}

resource "azurerm_network_security_group" "this" {
  for_each = var.security_groups

  name                = "${var.name_prefix}-${each.key}-nsg"
  resource_group_name = var.resource_group_name
  location            = var.location

  dynamic "security_rule" {
    for_each = each.value

    content {
      name                       = security_rule.key
      priority                   = security_rule.value.priority
      direction                  = "Inbound"
      access                     = security_rule.value.access
      protocol                   = security_rule.value.protocol
      source_port_range          = "*"
      destination_port_range     = security_rule.value.destination
      source_address_prefix      = security_rule.value.source
      destination_address_prefix = "*"
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "this" {
  for_each = var.security_groups

  subnet_id                 = var.subnet_ids[each.key]
  network_security_group_id = azurerm_network_security_group.this[each.key].id
}
