terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
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

variable "volumes" {
  type = map(object({
    size_gib     = number
    storage_type = string
    vm_id        = string
    lun          = number
  }))
}

resource "azurerm_managed_disk" "this" {
  for_each = var.volumes

  name                 = "${var.name_prefix}-vol-${each.key}"
  resource_group_name  = var.resource_group_name
  location             = var.location
  storage_account_type = each.value.storage_type
  create_option        = "Empty"
  disk_size_gb         = each.value.size_gib
}

resource "azurerm_virtual_machine_data_disk_attachment" "this" {
  for_each = var.volumes

  managed_disk_id    = azurerm_managed_disk.this[each.key].id
  virtual_machine_id = each.value.vm_id
  lun                = each.value.lun
  caching            = "None"
}
