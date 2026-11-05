variable "name_prefix" {
  description = "Préfixe de nommage, ex : myapp-dev"
  type        = string
}

variable "security_groups" {
  description = <<-EOT
    Security groups à créer (équivalent des NSG Azure).
    Chaque règle autorise un flux entrant depuis :
    - soit une plage d'IP (remote_ip_prefix),
    - soit un autre security group de cette map (remote_group).
  EOT
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

  # Une règle doit avoir exactement une source
  validation {
    condition = alltrue(flatten([
      for sg in values(var.security_groups) : [
        for r in values(sg.rules) : (r.remote_ip_prefix == null) != (r.remote_group == null)
      ]
    ]))
    error_message = "Chaque règle doit définir soit remote_ip_prefix, soit remote_group (pas les deux, pas aucun)."
  }

  # remote_group doit désigner un security group existant dans la map
  validation {
    condition = alltrue(flatten([
      for sg in values(var.security_groups) : [
        for r in values(sg.rules) : r.remote_group == null || contains(keys(var.security_groups), r.remote_group)
      ]
    ]))
    error_message = "remote_group doit correspondre à une clé de security_groups (ex : \"web\")."
  }
}
