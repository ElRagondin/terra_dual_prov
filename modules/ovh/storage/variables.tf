variable "name_prefix" {
  description = "Préfixe de nommage, ex : rpetri-dev"
  type        = string
}

variable "volumes" {
  description = "Volumes à créer : clé = nom du volume, avec sa taille (Go), son type et l'ID de la VM à laquelle l'attacher"
  type = map(object({
    size        = number
    type        = optional(string, "classic")
    instance_id = string
  }))

  validation {
    condition     = alltrue([for v in values(var.volumes) : v.size >= 10 && v.size <= 500])
    error_message = "La taille d'un volume doit être comprise entre 10 et 500 Go."
  }

  validation {
    condition     = alltrue([for v in values(var.volumes) : contains(["classic", "high-speed", "high-speed-gen2"], v.type)])
    error_message = "Le type de volume doit être classic, high-speed ou high-speed-gen2."
  }
}
