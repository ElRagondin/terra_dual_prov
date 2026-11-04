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
