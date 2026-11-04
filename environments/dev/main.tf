module "network" {
  source      = "../../modules/network"
  name_prefix = "${var.project}-${var.environment}"
  subnets     = var.subnets
}

module "security" {
  source          = "../../modules/security"
  name_prefix     = "${var.project}-${var.environment}"
  security_groups = var.security_groups
}

output "subnet_ids" {
  value = module.network.subnet_ids
}

output "security_group_ids" {
  value = module.security.security_group_ids
}
