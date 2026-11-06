# Déploiement et FinOps

Le workflow **Deploy dev, staging and production** se lance depuis **Actions → Run workflow**, sur **main**. Il attend un contrôle **Terraform CI** réussi pour le même commit avant de déployer.

1. **Estimation** : Infracost lit le Terraform du staging Azure si une clé est disponible. Sinon, le workflow calcule le tarif Azure avec l’API publique Azure Retail Prices. Les deux modes appliquent une seule fois le tarif des cinq premières règles du load balancer Standard. Le script lit en direct le catalogue public OVH France pour GRA11 et compare les deux totaux en EUR. Une PR du même dépôt qui touche le staging ou ses modules affiche l’estimation sans déployer.
2. **Dev** : déploiement sur le cloud choisi dans `dev_provider`.
3. **Staging** : déploiement sur le cloud le moins cher. À égalité exacte, le workflow conserve le staging déjà actif, ou choisit Azure si les deux workspaces sont vides.
4. **Prod** : promotion facultative vers **`prod-ovh`**. La décision FinOps ne s'applique pas à la prod.

Le mode par défaut (`deploy=false`) affiche les coûts. Cochez `verify_hcp` pour vérifier aussi les cinq workspaces, leurs états et la révision VCS sans créer de run Terraform. Chaque déploiement exécute automatiquement ce contrôle avant de modifier une ressource. Activez `deploy` pour dev et staging, puis `deploy_prod` pour poursuivre vers la production dans le même run. Protégez l'environnement GitHub **production** avec les approbations et les branches autorisées disponibles sur votre offre GitHub.

## Configuration initiale

- Secret GitHub facultatif **`INFRACOST_API_KEY`** : clé d'API Infracost. Sans clé, le workflow utilise les tarifs publics Azure.
- Secret GitHub **`HCP_TERRAFORM_TOKEN`** : jeton d'équipe HCP avec accès aux cinq workspaces, lecture de l'état et droits de plan, apply et discard. Utilisez un secret d'environnement distinct pour la prod si les droits sont séparés.
- Dans HCP, conservez les connexions VCS sur **main** et le dossier Terraform de chaque workspace : `environments/dev/azure`, `environments/dev/ovh`, `environments/staging/azure`, `environments/staging/ovh`, `environments/prod/ovh`. Vérifiez les identifiants cloud existants et la clé SSH de chacun.
- Désactivez les deux options **Auto-apply** et l'auto-destroy dans ces workspaces. Activez **Allow destroy plans** sur les quatre workspaces dev et staging si les bascules sont autorisées.

## Hypothèses et bascule

La comparaison utilise un mois de **730 h** aux tarifs publics HT, sans crédits, quotas gratuits, engagements ou remises. Elle exclut le trafic et les opérations variables. Azure inclut trois VM et leurs disques système, un disque de données, un load balancer et son IP publique. OVH inclut trois C3-4, leurs 150 Go de stockage local, 10 Go de stockage Classic, un load balancer Small et deux Floating IP. Les codes catalogue GRA11 sont définis dans le script. Le stockage local C3 est actuellement tarifé à zéro dans le catalogue public, ce qui relève du tarif produit et non d'un quota de compte. Une couverture incomplète arrête la pipeline. Les empreintes du Terraform empêchent de comparer une topologie modifiée avec des quantités obsolètes. Après un changement de configuration, vérifiez les postes et quantités dans `scripts/staging-cost.py`, puis mettez à jour les empreintes affichées par `python3 scripts/staging-cost.py --show-fingerprints`.

Le workflow sérialise les promotions et vérifie l'état des deux clouds. Pour une bascule, cochez **`allow_switch`** uniquement si vous acceptez de supprimer l'ancien environnement, y compris son disque PostgreSQL. Le workflow valide un plan du nouveau cloud, détruit l'ancien et vérifie que son état est vide avant d'appliquer le nouveau. Il n'y a pas de migration des données. Évitez les applies manuels concurrents. Après un apply échoué, vérifiez aussi les ressources orphelines côté cloud avant de reprendre. Les plans VCS en attente peuvent être écartés par la pipeline pour libérer la file HCP. Les politiques HCP restent appliquées.

Si HCP ne dispose pas d'une version VCS issue de main dont les fichiers correspondent à la révision GitHub, le workflow s'arrête. Initialisez le workspace VCS et vérifiez les filtres de chemins avant de réessayer.
