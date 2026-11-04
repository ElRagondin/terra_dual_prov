# Suffixe aléatoire : un nom de bucket doit être unique
resource "random_id" "suffix" {
  byte_length = 3
}

# Équivalent du Storage Account Azure (stockage des diagnostics)
resource "ovh_cloud_storage_object_bucket" "diagnostics" {
  service_name = var.project_id
  region       = var.region
  name         = "${var.name_prefix}-diag-${random_id.suffix.hex}"

  # Chiffrement côté serveur : les données sont chiffrées au repos
  encryption = {
    algorithm = "AES256"
  }

  # Ternaire : versioning activé ou non selon la variable
  versioning = {
    status = var.versioning ? "ENABLED" : "DISABLED"
  }

  # object_lock volontairement non défini : bug connu du provider v2.24.0
  # (github.com/ovh/terraform-provider-ovh/issues/1568)
}
