# Obligatoire dans le module : sans ça, Terraform chercherait "hashicorp/openstack"
terraform {
  required_providers {
    openstack = {
      source = "terraform-provider-openstack/openstack"
    }
  }
}
