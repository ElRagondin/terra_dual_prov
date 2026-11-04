variable "project" {
  description = "Nom de l'application"
  type        = string
}

variable "environment" {
  description = "Environnement cible"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment doit valoir dev, staging ou prod."
  }
}

variable "subnets" {
  description = "Sous-réseaux de l'environnement"
  type        = map(object({ cidr = string }))
}

variable "security_groups" {
  description = "Security groups de l'environnement"
  type = map(object({
    description = string
    rules = map(object({
      protocol         = string
      port_min         = optional(number)
      port_max         = optional(number)
      remote_ip_prefix = optional(string)
      remote_group     = optional(string)
    }))
  }))
}

variable "vms" {
  description = "VMs de l'environnement : sous-réseaux et security group désignés par leur rôle"
  type = map(object({
    count          = number
    flavor         = string
    subnets        = list(string)
    security_group = string
    user_data_file = optional(string)
  }))
}

variable "image_name" {
  description = "Image OVH des VMs"
  type        = string
  default     = "Ubuntu 24.04"
}

variable "public_key_path" {
  description = "Chemin de la clé publique SSH injectée dans les VMs"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "lb_flavor" {
  description = "Taille du Load Balancer (small, medium, large)"
  type        = string
  default     = "small"
}

variable "enable_admin_ip" {
  description = "Ajoute une IP publique sur web-1 pour l'administration SSH (à désactiver en prod)"
  type        = bool
  default     = false
}

variable "ovh_project_id" {
  description = "ID du projet Public Cloud OVH"
  type        = string
}
