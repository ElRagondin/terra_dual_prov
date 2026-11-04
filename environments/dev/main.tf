module "network" {
  source      = "../../modules/network"
  name_prefix = "${var.project}-${var.environment}"
  subnets     = var.subnets
}

output "subnet_ids" {
  value = module.network.subnet_ids
}
