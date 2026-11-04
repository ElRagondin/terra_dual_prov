output "public_ip" {
  description = "IP publique du Load Balancer"
  value       = openstack_networking_floatingip_v2.lb.address
}

output "url" {
  description = "URL de l'application"
  value       = "http://${openstack_networking_floatingip_v2.lb.address}"
}

output "loadbalancer_id" {
  description = "ID du Load Balancer"
  value       = openstack_lb_loadbalancer_v2.this.id
}
