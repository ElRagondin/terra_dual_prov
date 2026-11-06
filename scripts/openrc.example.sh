# Identifiants OpenStack et HCP lus dans Vault : aucun secret dans ce fichier
export VAULT_ADDR=https://127.0.0.1:8200
export VAULT_CACERT=$HOME/.vault-ca.crt
vault token lookup >/dev/null 2>&1 || vault login -no-print -method=userpass username=rudy

export OS_AUTH_URL=https://auth.cloud.ovh.net/v3
export OS_IDENTITY_API_VERSION=3
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_TENANT_ID=9ab75b8b6af0499ab5056a8f758a3d63
export OS_TENANT_NAME=8906114619564401
export OS_REGION_NAME=GRA11
export OS_USERNAME=$(vault kv get -field=username secret/terra/openstack)
export OS_PASSWORD=$(vault kv get -field=password secret/terra/openstack)
export TF_TOKEN_app_terraform_io=$(vault kv get -field=token secret/terra/hcp)
