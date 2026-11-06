# Tests du module security : aplatissement des règles, sources, validations
mock_provider "openstack" {}

variables {
  name_prefix = "test"
  security_groups = {
    web = {
      description = "web"
      rules = {
        ssh  = { protocol = "tcp", port_min = 22, port_max = 22, remote_ip_prefix = "203.0.113.10/32" }
        http = { protocol = "tcp", port_min = 80, port_max = 80, remote_ip_prefix = "10.10.1.0/24" }
      }
    }
    db = {
      description = "db"
      rules = {
        postgres = { protocol = "tcp", port_min = 5432, port_max = 5432, remote_group = "web" }
      }
    }
  }
}

run "regles_generees" {
  command = apply

  assert {
    condition     = length(openstack_networking_secgroup_v2.this) == 2
    error_message = "Deux security groups attendus (web, db)."
  }
  assert {
    condition     = length(openstack_networking_secgroup_rule_v2.this) == 3
    error_message = "Trois règles attendues après aplatissement."
  }
  assert {
    condition     = openstack_networking_secgroup_rule_v2.this["web-ssh"].remote_ip_prefix == "203.0.113.10/32"
    error_message = "Le SSH doit être limité à l'IP d'administration."
  }
  assert {
    condition     = openstack_networking_secgroup_rule_v2.this["db-postgres"].remote_group_id == openstack_networking_secgroup_v2.this["web"].id
    error_message = "PostgreSQL ne doit être ouvert qu'au groupe web."
  }
}

run "refuse_deux_sources" {
  command = plan
  variables {
    security_groups = {
      web = {
        description = "web"
        rules = {
          bad = { protocol = "tcp", port_min = 22, port_max = 22, remote_ip_prefix = "0.0.0.0/0", remote_group = "web" }
        }
      }
    }
  }
  expect_failures = [var.security_groups]
}

run "refuse_groupe_inconnu" {
  command = plan
  variables {
    security_groups = {
      db = {
        description = "db"
        rules = {
          postgres = { protocol = "tcp", port_min = 5432, port_max = 5432, remote_group = "inexistant" }
        }
      }
    }
  }
  expect_failures = [var.security_groups]
}
