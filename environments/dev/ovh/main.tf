# Environnement dev : toute l'infrastructure est décrite dans le module stack,
# seules les valeurs propres à l'environnement sont dans terraform.tfvars.
module "stack" {
  source = "../../../modules/ovh/stack"

  project         = var.project
  environment     = var.environment
  subnets         = var.subnets
  security_groups = var.security_groups
  vms             = var.vms
  image_name      = var.image_name
  public_key      = var.public_key
  lb_flavor       = var.lb_flavor
  enable_admin_ip = var.enable_admin_ip
  enable_https    = var.enable_https
  volumes         = var.volumes
}

output "app_url" { value = module.stack.app_url }
output "app_url_https" { value = module.stack.app_url_https }
output "admin_ssh" { value = module.stack.admin_ssh }
output "vm_private_ips" { value = module.stack.vm_private_ips }
output "subnet_ids" { value = module.stack.subnet_ids }
output "security_group_ids" { value = module.stack.security_group_ids }
output "volume_ids" { value = module.stack.volume_ids }

# Les ressources ont changé d'adresse : on l'indique à Terraform pour qu'il ne les recrée pas
moved {
  from = module.network
  to   = module.stack.module.network
}
moved {
  from = module.security
  to   = module.stack.module.security
}
moved {
  from = module.compute
  to   = module.stack.module.compute
}
moved {
  from = module.loadbalancer
  to   = module.stack.module.loadbalancer
}
moved {
  from = module.storage
  to   = module.stack.module.storage
}
moved {
  from = openstack_networking_floatingip_v2.admin
  to   = module.stack.openstack_networking_floatingip_v2.admin
}
moved {
  from = openstack_networking_floatingip_associate_v2.admin
  to   = module.stack.openstack_networking_floatingip_associate_v2.admin
}
