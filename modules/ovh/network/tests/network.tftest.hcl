# Tests du module network, sans cloud réel (provider simulé)
mock_provider "openstack" {
  mock_data "openstack_networking_network_v2" {
    defaults = { id = "ext-net-id" }
  }
}

variables {
  name_prefix = "test"
  subnets = {
    web = { cidr = "10.10.1.0/24" }
    db  = { cidr = "10.10.2.0/24" }
  }
}

run "reseau_et_sous_reseaux" {
  command = apply

  assert {
    condition     = length(openstack_networking_subnet_v2.this) == 2
    error_message = "Un sous-réseau par entrée de la map attendu."
  }
  assert {
    condition     = openstack_networking_subnet_v2.this["db"].cidr == "10.10.2.0/24"
    error_message = "Le CIDR du sous-réseau db est incorrect."
  }
  assert {
    condition     = length(openstack_networking_router_interface_v2.this) == 2
    error_message = "Chaque sous-réseau doit être relié au routeur."
  }
  assert {
    condition     = openstack_networking_router_v2.this.external_network_id == "ext-net-id"
    error_message = "Le routeur doit sortir sur Ext-Net."
  }
  assert {
    condition     = length(output.subnet_ids) == 2
    error_message = "L'output subnet_ids doit contenir les deux rôles."
  }
}

run "refuse_cidr_invalide" {
  command = plan
  variables {
    subnets = { web = { cidr = "10.10.1.0/33" } }
  }
  expect_failures = [var.subnets]
}
