project     = "myapp"
environment = "dev"

subnets = {
  web = { cidr = "10.10.1.0/24" }
  db  = { cidr = "10.10.2.0/24" }
}

security_groups = {
  web = {
    description = "Serveurs web : HTTP depuis le sous-reseau web (Load Balancer), SSH depuis l'admin"
    rules = {
      ssh  = { protocol = "tcp", port_min = 22, port_max = 22, remote_ip_prefix = "82.225.88.198/32" }
      http = { protocol = "tcp", port_min = 80, port_max = 80, remote_ip_prefix = "10.10.1.0/24" }
    }
  }
  db = {
    description = "Base de donnees : accessible uniquement depuis les serveurs web"
    rules = {
      postgres = { protocol = "tcp", port_min = 5432, port_max = 5432, remote_group = "web" }
      ssh      = { protocol = "tcp", port_min = 22, port_max = 22, remote_group = "web" }
    }
  }
}

vms = {
  web = { count = 2, flavor = "d2-2", subnets = ["web"], security_group = "web", user_data_file = "cloud-init/web.yaml" }
  db  = { count = 1, flavor = "d2-2", subnets = ["db"], security_group = "db" }
}
