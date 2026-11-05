terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "location" {
  type    = string
  default = "denmarkeast"
}

locals {
  name_prefix = "myapp-dev"

  subnets = {
    web = { cidr = "10.10.1.0/24" }
    db  = { cidr = "10.10.2.0/24" }
  }
}

resource "azurerm_resource_group" "this" {
  name     = "${local.name_prefix}-rg"
  location = var.location
}

module "network" {
  source = "../../../modules/azure/network"

  name_prefix         = local.name_prefix
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  vnet_cidr           = "10.10.0.0/16"
  subnets             = local.subnets
}

variable "public_key" {
  type        = string
  description = "Clé publique SSH de l'administrateur des VM."
}

module "compute" {
  source = "../../../modules/azure/compute"

  name_prefix         = local.name_prefix
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  subnet_ids          = module.network.subnet_ids
  public_key          = var.public_key
  web_subnet_cidr     = local.subnets.web.cidr
}

module "load_balancer" {
  source = "../../../modules/azure/load_balancer"

  name_prefix         = local.name_prefix
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  web_nic_ids         = module.compute.web_nic_ids
}

output "web_url" {
  value = "http://${module.load_balancer.public_ip}"
}

module "security" {
  source = "../../../modules/azure/security"

  name_prefix         = local.name_prefix
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  subnet_ids          = module.network.subnet_ids

  security_groups = {
    web = {
      allow-http = {
        priority    = 100
        access      = "Allow"
        protocol    = "Tcp"
        source      = "Internet"
        destination = "80"
      }

      allow-https = {
        priority    = 110
        access      = "Allow"
        protocol    = "Tcp"
        source      = "Internet"
        destination = "443"
      }
    }

    db = {
      allow-postgresql-from-web = {
        priority    = 100
        access      = "Allow"
        protocol    = "Tcp"
        source      = local.subnets.web.cidr
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
  source = "../../../modules/azure/storage"

  name_prefix         = local.name_prefix
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
