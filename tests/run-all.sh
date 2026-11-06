#!/usr/bin/env bash
# Lance les tests terraform de chaque module qui en possède (provider simulé : aucune ressource réelle créée)
set -uo pipefail
cd "$(dirname "$0")/.."
status=0
for dir in modules/*/*/; do
  [ -d "${dir}tests" ] || continue
  echo "===== ${dir%/}"
  (cd "$dir" && terraform init -backend=false -input=false >/dev/null && terraform test) || status=1
done
exit $status
