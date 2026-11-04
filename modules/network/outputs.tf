output "network_id" {
  description = "ID du réseau privé"
  value       = openstack_networking_network_v2.this.id
}

output "subnet_ids" {
  description = "IDs des sous-réseaux, indexés par rôle (ex : subnet_ids[\"web\"])"
  value       = { for role, subnet in openstack_networking_subnet_v2.this : role => subnet.id }
}

output "router_id" {
  description = "ID du routeur"
  value       = openstack_networking_router_v2.this.id
}
