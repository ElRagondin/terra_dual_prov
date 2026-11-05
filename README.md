# terra_dual_prov

Déploiement d'une infrastructure multi-environnement (dev, staging, prod) et multi-cloud (OVH Public Cloud et Azure) avec Terraform.

## Structure

- `modules/ovh/` : modules Terraform OVH (network, security, compute, loadbalancer, storage)
- `modules/azure/` : modules Terraform Azure
- `environments/<env>/<cloud>/` : configuration d'un environnement pour un cloud, avec son propre state
- `scripts/` : scripts d'automatisation
- `docs/` : documentation technique (architecture, déploiement, sécurité)
- `tests/` : tests automatisés

## Conventions

- Une branche par fonctionnalité (`feature/...`), fusion dans `main` par pull request relue
- Aucun secret dans le dépôt : identifiants OVH (`OS_*`, `OVH_*`) et Azure (`ARM_*`) passés par variables d'environnement
- Modules OVH et Azure avec la même interface (variables `name_prefix`, `subnets`, `security_groups`, `vms` et outputs équivalents)

## Utilisation

    cd environments/dev/ovh     # ou environments/dev/azure
    terraform init
    terraform plan
    terraform apply
