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

variable "public_key" {
  type = string
}

locals {
  admin_username = "azureuser"

  vm_subnets = {
    web-1 = "web"
    web-2 = "web"
    db    = "db"
  }
}

resource "azurerm_network_interface" "this" {
  for_each = local.vm_subnets

  name                = "${var.name_prefix}-${each.key}-nic"
  resource_group_name = var.resource_group_name
  location            = var.location

  ip_configuration {
    name                          = "private"
    subnet_id                     = var.subnet_ids[each.value]
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "this" {
  for_each = local.vm_subnets

  name                            = "${var.name_prefix}-${each.key}"
  resource_group_name             = var.resource_group_name
  location                        = var.location
  size                            = "Standard_B2ats_v2"
  admin_username                  = local.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.this[each.key].id]

  disk_controller_type = each.value == "db" ? "SCSI" : null

  custom_data = each.value == "web" ? filebase64("${path.module}/cloud-init-web.yaml") : base64encode(templatefile("${path.module}/cloud-init-db.yaml.tftpl", {
    web_cidr = var.web_subnet_cidr
  }))

  admin_ssh_key {
    username   = local.admin_username
    public_key = var.public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 64
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}


output "web_nic_ids" {
  value = {
    for name, nic in azurerm_network_interface.this :
    name => nic.id if local.vm_subnets[name] == "web"
  }
}

output "vm_ids" {
  value = {
    for name, vm in azurerm_linux_virtual_machine.this : name => vm.id
  }
}

variable "web_subnet_cidr" {
  type = string
}
