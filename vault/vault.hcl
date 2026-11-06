# Serveur Vault local : stockage chiffré sur disque, HTTPS, accessible uniquement depuis la VM
ui = true

storage "file" {
  path = "/opt/vault/data"
}

listener "tcp" {
  address       = "127.0.0.1:8200"
  tls_cert_file = "/opt/vault/tls/tls.crt"
  tls_key_file  = "/opt/vault/tls/tls.key"
}

api_addr = "https://127.0.0.1:8200"
