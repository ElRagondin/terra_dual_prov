# Politiques de sécurité et de coût pour l'infrastructure OVH (dev et staging)
policy {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = ">= 3.0.0, < 4.0.0"
    }
  }
  terraform_config {
    required_version = ">= 1.17"
  }
}

# Coût : seules les petites tailles de VM sont autorisées (OVH = environnements hors production)
resource_policy "openstack_compute_instance_v2" "allowed_flavors" {
  enforcement_level = "mandatory"

  locals {
    allowed = ["d2-2", "d2-4", "c3-4"]
  }

  enforce {
    condition     = core::contains(local.allowed, attrs.flavor_name)
    error_message = "Taille ${attrs.flavor_name} interdite sur OVH : tailles autorisées d2-2, d2-4, c3-4."
  }
}

# Sécurité : le SSH ne doit jamais être ouvert à tout Internet
resource_policy "openstack_networking_secgroup_rule_v2" "no_public_ssh" {
  enforcement_level = "mandatory"

  locals {
    open_to_world = attrs.remote_ip_prefix == "0.0.0.0/0" || attrs.remote_ip_prefix == "::/0"
    covers_ssh    = attrs.port_range_min == null ? false : (attrs.port_range_min <= 22 && attrs.port_range_max >= 22)
  }

  enforce {
    condition     = !(local.open_to_world && local.covers_ssh)
    error_message = "Une règle ouvre le port 22 à tout Internet : limiter la source à une IP d'administration (/32)."
  }
}

# Coût : volumes de données limités à 50 Go
resource_policy "openstack_blockstorage_volume_v3" "max_volume_size" {
  enforcement_level = "mandatory"

  enforce {
    condition     = attrs.size <= 50
    error_message = "Volume ${attrs.name} : ${attrs.size} Go demandés, 50 Go maximum."
  }
}
