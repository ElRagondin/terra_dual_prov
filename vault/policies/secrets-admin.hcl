# Administrateur : gère les secrets du projet
path "secret/data/terra/*" {
  capabilities = ["create", "read", "update", "delete"]
}
path "secret/metadata/terra/*" {
  capabilities = ["read", "list", "delete"]
}
