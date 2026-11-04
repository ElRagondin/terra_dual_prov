output "instance_ids" {
  description = "IDs des VMs, indexés par nom (web-1, web-2, db-1...)"
  value       = { for name, vm in openstack_compute_instance_v2.this : name => vm.id }
}

output "private_ips" {
  description = "IP privées des VMs, indexées par nom"
  value       = { for name, vm in openstack_compute_instance_v2.this : name => vm.access_ip_v4 }
}

output "private_ips_by_group" {
  description = "IP privées regroupées par rôle (utilisé par le Load Balancer)"
  value = {
    for group in keys(var.vm_groups) : group => [
      for name, vm in openstack_compute_instance_v2.this : vm.access_ip_v4 if local.instances[name].group == group
    ]
  }
}

output "port_ids" {
  description = "IDs des ports réseau (utiles pour associer une IP publique)"
  value       = { for key, port in openstack_networking_port_v2.this : key => port.id }
}
