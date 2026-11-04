variable "name_prefix" {
  description = "Préfixe de nommage, ex : myapp-dev (remplace le Resource Group Azure)"
  type        = string
}

variable "subnets" {
  description = "Sous-réseaux à créer : clé = rôle (web, db...), valeur = CIDR"
  type = map(object({
    cidr = string
  }))

  validation {
    condition     = alltrue([for s in values(var.subnets) : can(cidrhost(s.cidr, 0))])
    error_message = "Chaque sous-réseau doit avoir un CIDR valide (ex : 10.10.1.0/24)."
  }
}

variable "dns_nameservers" {
  description = "Serveurs DNS distribués aux VMs"
  type        = list(string)
  default     = ["213.186.33.99", "1.1.1.1"]
}

variable "external_network_name" {
  description = "Réseau public OVH"
  type        = string
  default     = "Ext-Net"
}
