locals {
  # { web = { count = 2 } } devient { "web-1" = {...}, "web-2" = {...} }
  instances = merge([
    for group, cfg in var.vm_groups : {
      for i in range(cfg.count) : format("%s-%d", group, i + 1) => merge(cfg, { group = group })
    }
  ]...)

  # Une carte réseau (port) par VM et par sous-réseau : "web-1-nic0", "web-1-nic1"...
  nics = merge([
    for name, vm in local.instances : {
      for idx, subnet_id in vm.subnet_ids : format("%s-nic%d", name, idx) => {
        instance           = name
        subnet_id          = subnet_id
        security_group_ids = vm.security_group_ids
      }
    }
  ]...)

  # Ternaire : clé créée par le module ou clé existante
  key_pair_name = var.create_keypair ? openstack_compute_keypair_v2.this[0].name : var.existing_keypair_name
}

# count + ternaire : 1 paire de clés si demandée, 0 sinon
resource "openstack_compute_keypair_v2" "this" {
  count = var.create_keypair ? 1 : 0

  name       = "${var.name_prefix}-key"
  public_key = var.public_key
}

# Image la plus récente portant ce nom
data "openstack_images_image_v2" "this" {
  name        = var.image_name
  most_recent = true
}

# Ports réseau : chaque port est placé dans son sous-réseau et porte les security groups
resource "openstack_networking_port_v2" "this" {
  for_each = local.nics

  name               = "${var.name_prefix}-${each.key}"
  network_id         = var.network_id
  admin_state_up     = true
  security_group_ids = each.value.security_group_ids

  fixed_ip {
    subnet_id = each.value.subnet_id
  }
}

# VMs : for_each plutôt que count, pour des noms stables (web-1, web-2, db-1)
resource "openstack_compute_instance_v2" "this" {
  for_each = local.instances

  name        = "${var.name_prefix}-${each.key}"
  image_id    = data.openstack_images_image_v2.this.id
  flavor_name = each.value.flavor
  key_pair    = local.key_pair_name
  user_data   = each.value.user_data

  metadata = {
    group = each.value.group
  }

  # Bloc dynamique : une carte réseau par port appartenant à cette VM
  dynamic "network" {
    for_each = [for key, nic in local.nics : openstack_networking_port_v2.this[key].id if nic.instance == each.key]
    content {
      port = network.value
    }
  }
}
