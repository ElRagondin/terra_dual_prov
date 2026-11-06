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
}

variable "public_key" {
  type = string
}

variable "web_source_cidr" {
  type    = string
  default = "82.96.158.190/32"
}

resource "azurerm_resource_group" "this" {
  name     = "${var.name_prefix}-rg"
  location = var.location
}

module "network" {
  source = "../network"

  name_prefix         = var.name_prefix
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  vnet_cidr           = var.vnet_cidr
  subnets             = var.subnets
}

module "compute" {
  source = "../compute"

  name_prefix         = var.name_prefix
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  subnet_ids          = module.network.subnet_ids
  public_key          = var.public_key
  web_subnet_cidr     = var.subnets["web"].cidr
}

module "load_balancer" {
  source = "../load_balancer"

  name_prefix         = var.name_prefix
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  web_nic_ids         = module.compute.web_nic_ids
}

module "security" {
  source = "../security"

  name_prefix         = var.name_prefix
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  subnet_ids          = module.network.subnet_ids

  security_groups = {
    web = {
      allow-http = {
        priority    = 100
        access      = "Allow"
        protocol    = "Tcp"
        source      = var.web_source_cidr
        destination = "80"
      }

      allow-https = {
        priority    = 110
        access      = "Allow"
        protocol    = "Tcp"
        source      = var.web_source_cidr
        destination = "443"
      }
    }

    db = {
      allow-postgresql-from-web = {
        priority    = 100
        access      = "Allow"
        protocol    = "Tcp"
        source      = var.subnets["web"].cidr
        destination = "5432"
      }

      deny-other-inbound = {
        priority    = 200
        access      = "Deny"
        protocol    = "*"
        source      = "*"
        destination = "*"
      }
    }
  }
}

module "storage" {
  source = "../storage"

  name_prefix         = var.name_prefix
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  volumes = {
    pgdata = {
      size_gib     = 10
      storage_type = "StandardSSD_LRS"
      vm_id        = module.compute.vm_ids["db"]
      lun          = 0
    }
  }
}

output "web_url" {
  value = "http://${module.load_balancer.public_ip}"
}
