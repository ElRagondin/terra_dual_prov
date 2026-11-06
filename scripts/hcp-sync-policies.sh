#!/usr/bin/env bash
# Synchronise le dossier policies/ vers HCP Terraform :
# un policy set "Terraform policy" limité au projet, et une politique individuelle par fichier .policy.hcl.
# Le dépôt Git reste la source de vérité. Prérequis : terraform login (ou TFE_TOKEN), jq.
set -euo pipefail

ORG="terra_dual_prov"
PROJECT="terra_dual_prov"
SET_NAME="securite-et-couts"
SET_DESC="Tailles de VM, SSH public et taille des volumes (OVH et Azure) - synchronisé depuis Git"
POLICY_DIR="policies"
API="https://app.terraform.io/api/v2"
TOKEN="${TF_TOKEN_app_terraform_io:-$(vault kv get -field=token secret/terra/hcp)}"
AUTH=(-H "Authorization: Bearer $TOKEN")
JSON=(-H "Content-Type: application/vnd.api+json")

# Appel API : affiche le corps de la réponse, ou l'erreur complète si le code HTTP n'est pas 2xx
api() {
  local method=$1 path=$2 data=${3:-} out code
  if [ -n "$data" ]; then
    out=$(curl -s -w '\n%{http_code}' -X "$method" "${AUTH[@]}" "${JSON[@]}" "$API$path" -d "$data")
  else
    out=$(curl -s -w '\n%{http_code}' -X "$method" "${AUTH[@]}" "$API$path")
  fi
  code=$(tail -n1 <<<"$out")
  if [ "$code" -ge 300 ]; then
    echo "ERREUR $code sur $method $path :" >&2
    sed '$d' <<<"$out" | jq . >&2 2>/dev/null || sed '$d' <<<"$out" >&2
    return 1
  fi
  sed '$d' <<<"$out"
}

# 1. Projet ciblé
PROJECT_ID=$(api GET "/organizations/$ORG/projects?page%5Bsize%5D=100" \
  | jq -r --arg n "$PROJECT" '.data[] | select(.attributes.name==$n) | .id')
echo "Projet $PROJECT : $PROJECT_ID"

# 2. Policy set (créé s'il n'existe pas)
SET_ID=$(api GET "/organizations/$ORG/policy-sets?page%5Bsize%5D=100" \
  | jq -r --arg n "$SET_NAME" '.data[] | select(.attributes.name==$n) | .id')
if [ -z "$SET_ID" ]; then
  SET_ID=$(api POST "/organizations/$ORG/policy-sets" "$(jq -n \
    --arg n "$SET_NAME" --arg d "$SET_DESC" --arg p "$PROJECT_ID" \
    '{data:{type:"policy-sets",attributes:{name:$n,description:$d,kind:"tfpolicy",global:false},
      relationships:{projects:{data:[{id:$p,type:"projects"}]}}}}')" | jq -r .data.id)
  echo "Policy set créé : $SET_ID"
else
  echo "Policy set existant : $SET_ID"
fi

# 3. Une politique par fichier : création si besoin, rattachement au set, envoi du contenu
EXISTING=$(api GET "/organizations/$ORG/policies?page%5Bsize%5D=100")
for file in "$POLICY_DIR"/*.policy.hcl; do
  name="politiques-$(basename "$file" .policy.hcl)"
  POL_ID=$(jq -r --arg n "$name" '.data[] | select(.attributes.name==$n) | .id' <<<"$EXISTING")
  if [ -z "$POL_ID" ]; then
    POL_ID=$(api POST "/organizations/$ORG/policies" "$(jq -n --arg n "$name" --arg s "$SET_ID" --arg f "$file" \
      '{data:{type:"policies",attributes:{name:$n,description:("Synchronisé depuis "+$f),kind:"tfpolicy"},
        relationships:{"policy-sets":{data:[{id:$s,type:"policy-sets"}]}}}}')" | jq -r .data.id)
    echo "Politique créée : $name ($POL_ID)"
  else
    api POST "/policy-sets/$SET_ID/relationships/policies" \
      "$(jq -n --arg p "$POL_ID" '{data:[{id:$p,type:"policies"}]}')" >/dev/null || true
  fi
  CODE=$(curl -s -o /tmp/upload.out -w '%{http_code}' -X PUT "${AUTH[@]}" \
    -H "Content-Type: application/octet-stream" --data-binary @"$file" "$API/policies/$POL_ID/upload")
  if [ "$CODE" -ge 300 ]; then echo "ERREUR $CODE à l'envoi de $file :"; cat /tmp/upload.out; exit 1; fi
  echo "Contenu envoyé : $file -> $name ($CODE)"
done

echo "Synchronisation terminée."
