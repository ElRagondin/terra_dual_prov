# Tests du module compute : for_each, ports dynamiques, clé SSH (count + ternaire), validations
mock_provider "openstack" {}

variables {
  name_prefix = "test"
  network_id  = "net-id"
  public_key  = "ssh-ed25519 AAAAtest test@example"
  vm_groups = {
    web = { count = 2, flavor = "c3-4", subnet_ids = ["subnet-web"], security_group_ids = ["sg-web"], user_data = "#cloud-config" }
    db  = { count = 1, flavor = "c3-4", subnet_ids = ["subnet-db"], security_group_ids = ["sg-db"] }
  }
}

run "vms_et_ports" {
  command = apply

  assert {
    condition     = length(openstack_compute_instance_v2.this) == 3
    error_message = "Trois VMs attendues (2 web + 1 db)."
  }
  assert {
    condition     = openstack_compute_instance_v2.this["web-2"].name == "test-web-2"
    error_message = "Nommage attendu : <prefixe>-<groupe>-<numéro>."
  }
  assert {
    condition     = length(openstack_networking_port_v2.this) == 3
    error_message = "Un port réseau par VM et par sous-réseau attendu."
  }
  assert {
    condition     = contains(openstack_networking_port_v2.this["db-1-nic0"].security_group_ids, "sg-db")
    error_message = "Le port de la base doit porter le security group db."
  }
  assert {
    condition     = length(openstack_compute_keypair_v2.this) == 1
    error_message = "La paire de clés doit être créée quand create_keypair = true."
  }
}

run "cle_existante" {
  command = apply
  variables {
    create_keypair        = false
    existing_keypair_name = "cle-existante"
    public_key            = null
  }

  assert {
    condition     = length(openstack_compute_keypair_v2.this) == 0
    error_message = "Aucune paire de clés ne doit être créée."
  }
  assert {
    condition     = openstack_compute_instance_v2.this["web-1"].key_pair == "cle-existante"
    error_message = "Les VMs doivent utiliser la clé existante."
  }
}

run "refuse_trop_de_vms" {
  command = plan
  variables {
    vm_groups = {
      web = { count = 6, flavor = "c3-4", subnet_ids = ["s"], security_group_ids = ["g"] }
    }
  }
  expect_failures = [var.vm_groups]
}

run "refuse_cle_manquante" {
  command = plan
  variables {
    public_key = null
  }
  expect_failures = [var.public_key]
}
