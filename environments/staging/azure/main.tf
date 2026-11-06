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

variable "web_source_cidr" {
  type    = string
  default = "82.96.158.190/32"

  validation {
    condition     = can(cidrnetmask(var.web_source_cidr)) && endswith(var.web_source_cidr, "/32")
    error_message = "Use a single IPv4 address with a /32 prefix."
  }
}

module "stack" {
  source = "../../../modules/azure/stack"

  name_prefix     = "myapp-staging"
  # Taille Standard_B2ats_v2 validée dans cette région.
  location        = "spaincentral"
  vnet_cidr       = "10.11.0.0/16"
  public_key      = var.public_key
  web_source_cidr = var.web_source_cidr

  subnets = {
    web = { cidr = "10.11.1.0/24" }
    db  = { cidr = "10.11.2.0/24" }
  }
}

output "web_url" {
  value = module.stack.web_url
}
