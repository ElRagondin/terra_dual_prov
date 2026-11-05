# Réseau public OVH existant, récupéré en lecture seule
data "openstack_networking_network_v2" "external" {
  name = var.external_network_name
}

# Équivalent du Virtual Network Azure
resource "openstack_networking_network_v2" "this" {
  name           = "${var.name_prefix}-net"
  admin_state_up = true
}

# Un sous-réseau par entrée de la map : en ajouter un = ajouter une ligne dans le tfvars
resource "openstack_networking_subnet_v2" "this" {
  for_each = var.subnets

  name            = "${var.name_prefix}-subnet-${each.key}"
  network_id      = openstack_networking_network_v2.this.id
  cidr            = each.value.cidr
  ip_version      = 4
  dns_nameservers = var.dns_nameservers
}

# Routeur vers Internet (produit "Gateway" chez OVH, nécessaire pour les floating IP)
resource "openstack_networking_router_v2" "this" {
  name                = "${var.name_prefix}-router"
  admin_state_up      = true
  external_network_id = data.openstack_networking_network_v2.external.id
}

# Raccordement de chaque sous-réseau au routeur
resource "openstack_networking_router_interface_v2" "this" {
  for_each = openstack_networking_subnet_v2.this

  router_id = openstack_networking_router_v2.this.id
  subnet_id = each.value.id
}
