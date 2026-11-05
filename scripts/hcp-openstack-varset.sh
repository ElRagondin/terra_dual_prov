#!/usr/bin/env bash
# Crée ou met à jour le variable set HCP "openstack-gra11" à partir de la session courante,
# puis le rattache aux workspaces OVH. À relancer à chaque changement de compte OpenStack.
# Prérequis : source ~/.secrets/openrc.sh et terraform login.
set -euo pipefail

ORG="terra_dual_prov"
VARSET_NAME="openstack-gra11"
WORKSPACES=("dev-ovh" "staging-ovh")
API="https://app.terraform.io/api/v2"
TOKEN=$(jq -r '.credentials["app.terraform.io"].token' ~/.terraform.d/credentials.tfrc.json)
H=(-H "Authorization: Bearer $TOKEN" -H "Content-Type: application/vnd.api+json")

: "${OS_USERNAME:?Charger d'abord ~/.secrets/openrc.sh}"
: "${OS_PASSWORD:?Charger d'abord ~/.secrets/openrc.sh}"

VARS=$(jq -n \
  --arg auth "$OS_AUTH_URL" --arg reg "$OS_REGION_NAME" --arg tid "$OS_TENANT_ID" --arg tname "$OS_TENANT_NAME" \
  --arg user "$OS_USERNAME" --arg pass "$OS_PASSWORD" --arg key "$(cat ~/.ssh/id_ed25519.pub)" \
  '[
    {key:"OS_AUTH_URL",             value:$auth,     category:"env",       sensitive:false},
    {key:"OS_IDENTITY_API_VERSION", value:"3",       category:"env",       sensitive:false},
    {key:"OS_USER_DOMAIN_NAME",     value:"Default", category:"env",       sensitive:false},
    {key:"OS_PROJECT_DOMAIN_NAME",  value:"Default", category:"env",       sensitive:false},
    {key:"OS_REGION_NAME",          value:$reg,      category:"env",       sensitive:false},
    {key:"OS_TENANT_ID",            value:$tid,      category:"env",       sensitive:false},
    {key:"OS_TENANT_NAME",          value:$tname,    category:"env",       sensitive:false},
    {key:"OS_USERNAME",             value:$user,     category:"env",       sensitive:false},
    {key:"OS_PASSWORD",             value:$pass,     category:"env",       sensitive:true},
    {key:"public_key",              value:$key,      category:"terraform", sensitive:false}
  ]')

# Création du variable set s'il n'existe pas
VARSET_ID=$(curl -s "${H[@]}" "$API/organizations/$ORG/varsets" \
  | jq -r --arg n "$VARSET_NAME" '.data[] | select(.attributes.name==$n) | .id')
if [ -z "$VARSET_ID" ]; then
  VARSET_ID=$(curl -s "${H[@]}" -X POST "$API/organizations/$ORG/varsets" \
    -d "$(jq -n --arg n "$VARSET_NAME" '{data:{type:"varsets",attributes:{name:$n,global:false,
         description:"Identifiants OpenStack OVH GRA11 et clé SSH (scripts/hcp-openstack-varset.sh)"}}}')" \
    | jq -r .data.id)
  echo "Variable set créé : $VARSET_ID"
fi

# Création ou mise à jour de chaque variable
EXISTING=$(curl -s "${H[@]}" "$API/varsets/$VARSET_ID/relationships/vars")
echo "$VARS" | jq -c '.[]' | while read -r v; do
  KEY=$(echo "$v" | jq -r .key)
  VAR_ID=$(echo "$EXISTING" | jq -r --arg k "$KEY" '.data[] | select(.attributes.key==$k) | .id')
  BODY=$(echo "$v" | jq '{data:{type:"vars",attributes:.}}')
  if [ -z "$VAR_ID" ]; then
    CODE=$(curl -s -o /dev/null -w '%{http_code}' "${H[@]}" -X POST "$API/varsets/$VARSET_ID/relationships/vars" -d "$BODY")
  else
    CODE=$(curl -s -o /dev/null -w '%{http_code}' "${H[@]}" -X PATCH "$API/varsets/$VARSET_ID/relationships/vars/$VAR_ID" -d "$BODY")
  fi
  echo "  $KEY : $CODE"
done

# Rattachement aux workspaces
WS_DATA=$(for ws in "${WORKSPACES[@]}"; do
  curl -s "${H[@]}" "$API/organizations/$ORG/workspaces/$ws" | jq '{type:"workspaces",id:.data.id}'
done | jq -s '{data:.}')
CODE=$(curl -s -o /dev/null -w '%{http_code}' "${H[@]}" -X POST "$API/varsets/$VARSET_ID/relationships/workspaces" -d "$WS_DATA")
echo "Rattachement à ${WORKSPACES[*]} : $CODE"
