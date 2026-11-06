terraform {
  cloud {
    organization = "terra_dual_prov"
    workspaces {
      name = "prod-ovh"
    }
  }

  required_version = ">= 1.6"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.0"
    }
  }
}

# Identifiants lus depuis les variables OS_* (fichier ~/.secrets/openrc.sh) : aucun secret dans le code.
# Projet OVH fourni par la formation : on passe directement par OpenStack, sans le provider ovh.
provider "openstack" {}
