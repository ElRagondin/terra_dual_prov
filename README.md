# terra_dual_prov

Déploiement d'une infrastructure multi-environnement (dev, staging, prod) sur OVH Public Cloud avec Terraform.

## Structure

- `environments/` : configuration de chaque environnement
- `modules/` : modules Terraform réutilisables (network, security, compute, loadbalancer)
- `scripts/` : scripts d'automatisation
- `docs/` : documentation technique (architecture, déploiement, sécurité)
- `tests/` : tests automatisés
