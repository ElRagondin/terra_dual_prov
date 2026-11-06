# Obligatoire dans le module : sans ça, Terraform chercherait "hashicorp/openstack"
terraform {
  required_version = ">= 1.6"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.0"
    }
  }
}
