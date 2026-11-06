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

variable "public_key" {
  type        = string
  description = "Clé publique SSH de l'administrateur des VM."
}

module "stack" {
  source = "../../../modules/azure/stack"

  name_prefix = "myapp-staging"
  # Taille Standard_B2ats_v2 validée dans cette région.
  location   = "spaincentral"
  vnet_cidr  = "10.11.0.0/16"
  public_key = var.public_key

  subnets = {
    web = { cidr = "10.11.1.0/24" }
    db  = { cidr = "10.11.2.0/24" }
  }
}

output "web_url" {
  value = module.stack.web_url
}
