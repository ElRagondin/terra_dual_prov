locals {
  name_prefix = "${var.project}-${var.environment}"
}

module "network" {
  source      = "../../modules/network"
  name_prefix = local.name_prefix
  subnets     = var.subnets
}

module "security" {
  source          = "../../modules/security"
  name_prefix     = local.name_prefix
  security_groups = var.security_groups
}

module "compute" {
  source      = "../../modules/compute"
  name_prefix = local.name_prefix
  network_id  = module.network.network_id
  image_name  = var.image_name
  public_key  = file(pathexpand(var.public_key_path))

  # Traduction des rôles ("web", "db") en IDs fournis par les autres modules
  vm_groups = {
    for name, vm in var.vms : name => {
      count              = vm.count
      flavor             = vm.flavor
      subnet_ids         = [for s in vm.subnets : module.network.subnet_ids[s]]
      security_group_ids = [module.security.security_group_ids[vm.security_group]]
      user_data          = vm.user_data_file != null ? file("${path.module}/${vm.user_data_file}") : null
    }
  }
}

output "subnet_ids" {
  value = module.network.subnet_ids
}

output "security_group_ids" {
  value = module.security.security_group_ids
}

output "vm_private_ips" {
  value = module.compute.private_ips
}

module "loadbalancer" {
  source           = "../../modules/loadbalancer"
  name_prefix      = local.name_prefix
  vip_subnet_id    = module.network.subnet_ids["web"]
  member_subnet_id = module.network.subnet_ids["web"]
  flavor_name      = var.lb_flavor

  # Seules les VMs web sont ajoutées au pool
  members = { for name, ip in module.compute.private_ips : name => ip if startswith(name, "web-") }
}

# IP d'administration SSH sur web-1, créée seulement si enable_admin_ip = true
resource "openstack_networking_floatingip_v2" "admin" {
  count       = var.enable_admin_ip ? 1 : 0
  pool        = "Ext-Net"
  description = "${local.name_prefix} - acces SSH admin"
}

resource "openstack_networking_floatingip_associate_v2" "admin" {
  count       = var.enable_admin_ip ? 1 : 0
  floating_ip = openstack_networking_floatingip_v2.admin[0].address
  port_id     = module.compute.port_ids["web-1-nic0"]
}

output "app_url" {
  value = module.loadbalancer.url
}

output "admin_ssh" {
  description = "Commande SSH vers web-1 (null si enable_admin_ip = false)"
  value       = one(openstack_networking_floatingip_v2.admin[*].address) != null ? "ssh ubuntu@${one(openstack_networking_floatingip_v2.admin[*].address)}" : null
}
