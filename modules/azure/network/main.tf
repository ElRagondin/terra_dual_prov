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

variable "vnet_cidr" {
  type = string
}

variable "subnets" {
  type = map(object({
    cidr = string
  }))

  validation {
    condition     = alltrue([for subnet in values(var.subnets) : can(cidrhost(subnet.cidr, 0))])
    error_message = "Chaque sous-réseau doit avoir un CIDR valide."
  }
}

resource "azurerm_virtual_network" "this" {
  name                = "${var.name_prefix}-vnet"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = [var.vnet_cidr]
}

resource "azurerm_subnet" "this" {
  for_each = var.subnets

  name                 = "${var.name_prefix}-subnet-${each.key}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [each.value.cidr]
}

output "network_id" {
  value = azurerm_virtual_network.this.id
}

output "subnet_ids" {
  value = { for role, subnet in azurerm_subnet.this : role => subnet.id }
}
