variable "name_prefix" {
  description = "Préfixe de nommage, ex : myapp-dev"
  type        = string
}

variable "vip_subnet_id" {
  description = "Sous-réseau où le Load Balancer reçoit le trafic"
  type        = string
}

variable "member_subnet_id" {
  description = "Sous-réseau des serveurs web (membres du pool)"
  type        = string
}

variable "members" {
  description = "Serveurs web à répartir : clé = nom de la VM, valeur = IP privée"
  type        = map(string)
}

variable "flavor_name" {
  description = "Taille du Load Balancer OVH (small, medium, large) ; null = taille par défaut"
  type        = string
  default     = "small"
}

variable "port" {
  description = "Port HTTP exposé et utilisé sur les serveurs web"
  type        = number
  default     = 80
}

variable "health_check_path" {
  description = "URL testée par le health check"
  type        = string
  default     = "/"
}

variable "external_network_name" {
  description = "Réseau public OVH d'où provient la floating IP"
  type        = string
  default     = "Ext-Net"
}
