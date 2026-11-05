terraform {
  required_version = ">= 1.6"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.0"
    }
    ovh = {
      source  = "ovh/ovh"
      version = "~> 2.0"
    }
  }
}

# Identifiants lus depuis les variables OS_* et OVH_* : aucun secret dans le code
provider "openstack" {}
provider "ovh" {}
