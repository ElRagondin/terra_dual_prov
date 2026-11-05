output "security_group_ids" {
  description = "IDs des security groups, indexés par rôle (ex : security_group_ids[\"web\"])"
  value       = { for role, sg in openstack_networking_secgroup_v2.this : role => sg.id }
}

output "security_group_names" {
  description = "Noms des security groups, indexés par rôle (utilisés par les instances)"
  value       = { for role, sg in openstack_networking_secgroup_v2.this : role => sg.name }
}
