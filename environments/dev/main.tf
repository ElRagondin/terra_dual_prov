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
