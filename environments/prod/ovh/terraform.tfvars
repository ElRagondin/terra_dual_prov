project     = "rpetri"
environment = "prod"

subnets = {
  web = { cidr = "10.12.1.0/24" }
  db  = { cidr = "10.12.2.0/24" }
}

security_groups = {
  web = {
    description = "Serveurs web : HTTP depuis le sous-reseau web (Load Balancer) - demo"
    rules = {
      http  = { protocol = "tcp", port_min = 80, port_max = 80, remote_ip_prefix = "10.12.1.0/24" }
      https = { protocol = "tcp", port_min = 443, port_max = 443, remote_ip_prefix = "10.12.1.0/24" }
    }
  }
  db = {
    description = "Base de donnees : accessible uniquement depuis les serveurs web"
    rules = {
      postgres = { protocol = "tcp", port_min = 5432, port_max = 5432, remote_group = "web" }
    }
  }
}

vms = {
  web = { count = 2, flavor = "c3-4", subnets = ["web"], security_group = "web", user_data_file = "cloud-init/web.yaml" }
  db  = { count = 1, flavor = "c3-4", subnets = ["db"], security_group = "db", user_data_file = "cloud-init/db.yaml.tftpl" }
}

lb_flavor       = "small"
enable_admin_ip = false


volumes = {
  pgdata = { size = 20, type = "classic", instance = "db-1" }
}

enable_https = true
