variable "name_prefix" {
  description = "Préfixe de nommage, ex : myapp-dev"
  type        = string
}

variable "network_id" {
  description = "ID du réseau privé (sortie du module network)"
  type        = string
}

variable "image_name" {
  description = "Nom de l'image OVH à utiliser"
  type        = string
  default     = "Ubuntu 24.04"
}

variable "create_keypair" {
  description = "true : crée la paire de clés SSH ; false : réutilise existing_keypair_name"
  type        = bool
  default     = true
}

variable "public_key" {
  description = "Clé publique SSH (requise si create_keypair = true)"
  type        = string
  default     = null

  validation {
    condition     = !var.create_keypair || var.public_key != null
    error_message = "public_key est obligatoire quand create_keypair = true."
  }
}

variable "existing_keypair_name" {
  description = "Nom d'une paire de clés existante (si create_keypair = false)"
  type        = string
  default     = null
}

variable "vm_groups" {
  description = "Groupes de VMs : clé = rôle (web, db...), avec leur nombre, taille, sous-réseaux et security groups"
  type = map(object({
    count              = number
    flavor             = string
    subnet_ids         = list(string)
    security_group_ids = list(string)
    user_data          = optional(string)
  }))

  validation {
    condition     = alltrue([for g in values(var.vm_groups) : g.count >= 0 && g.count <= 5])
    error_message = "Le nombre de VMs par groupe doit être compris entre 0 et 5."
  }

  validation {
    condition     = alltrue([for g in values(var.vm_groups) : length(g.subnet_ids) >= 1])
    error_message = "Chaque groupe doit être rattaché à au moins un sous-réseau."
  }
}
