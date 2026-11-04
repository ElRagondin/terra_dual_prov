project     = "myapp"
environment = "dev"

subnets = {
  web = { cidr = "10.10.1.0/24" }
  db  = { cidr = "10.10.2.0/24" }
}
