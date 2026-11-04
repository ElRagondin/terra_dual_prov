variable "name_prefix" {
  description = "Préfixe de nommage, ex : myapp-dev"
  type        = string
}

variable "project_id" {
  description = "ID du projet Public Cloud OVH"
  type        = string
}

variable "region" {
  description = "Région Object Storage OVH (ex : GRA, SBG, EU-WEST-PAR)"
  type        = string
  default     = "GRA"
}

variable "versioning" {
  description = "Active le versioning des objets"
  type        = bool
  default     = true
}
