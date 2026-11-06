# Tests du module storage : volume, attachement, valeur par défaut et validations
mock_provider "openstack" {}

variables {
  name_prefix = "test"
  volumes = {
    pgdata = { size = 10, instance_id = "vm-db" }
  }
}

run "volume_attache" {
  command = apply

  assert {
    condition     = openstack_blockstorage_volume_v3.this["pgdata"].name == "test-vol-pgdata"
    error_message = "Nom de volume incorrect."
  }
  assert {
    condition     = openstack_blockstorage_volume_v3.this["pgdata"].volume_type == "classic"
    error_message = "Le type par défaut doit être classic."
  }
  assert {
    condition     = openstack_compute_volume_attach_v2.this["pgdata"].instance_id == "vm-db"
    error_message = "Le volume doit être attaché à la VM de la base."
  }
}

run "refuse_taille_trop_petite" {
  command = plan
  variables {
    volumes = { pgdata = { size = 5, instance_id = "vm-db" } }
  }
  expect_failures = [var.volumes]
}

run "refuse_type_inconnu" {
  command = plan
  variables {
    volumes = { pgdata = { size = 10, type = "ultra", instance_id = "vm-db" } }
  }
  expect_failures = [var.volumes]
}
