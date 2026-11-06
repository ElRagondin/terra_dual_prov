# Déploiement et FinOps

Le workflow **Deploy dev, staging and production** se lance depuis **Actions → Run workflow**, sur **main**. Il attend un contrôle **Terraform CI** réussi pour le même commit avant de déployer.

1. **Estimation** : Infracost lit le Terraform du staging Azure et fournit son total en EUR. Le script lit le catalogue public OVH France au moment du run pour GRA11 et compare les deux totaux.
2. **Dev** : déploiement sur le cloud choisi dans `dev_provider`.
3. **Staging** : déploiement sur le cloud le moins cher. À égalité exacte, le workflow conserve le staging déjà actif, ou choisit Azure si les deux workspaces sont vides.
4. **Prod** : promotion facultative vers **`prod-ovh`**. La décision FinOps ne s'applique pas à la prod.

Le mode par défaut (`deploy=false`) affiche seulement les coûts. Activez `deploy` pour dev et staging, puis `deploy_prod` pour poursuivre vers la production dans le même run. Protégez l'environnement GitHub **production** avec les approbations et les branches autorisées disponibles sur votre offre GitHub.

## Configuration initiale

- Secret GitHub **`INFRACOST_API_KEY`** : clé d'API Infracost.
- Secret GitHub **`HCP_TERRAFORM_TOKEN`** : jeton d'équipe HCP avec accès aux cinq workspaces, lecture de l'état et droits de plan, apply et discard. Utilisez un secret d'environnement distinct pour la prod si les droits sont séparés.
- Variable GitHub **`OVH_STAGING_PRICE_CODES`** : objet JSON associant les cinq postes à leurs codes exacts du catalogue OVH pour GRA11. La commande `python3 scripts/staging-cost.py --list-ovh-codes` affiche des candidats avec leurs tarifs horaires. Vérifiez leurs unités sur le catalogue avant de les renseigner. Les clés attendues sont `c3-4`, `boot-storage`, `pgdata-classic`, `load-balancer-small`, `floating-ip`.
- Dans HCP, conservez les connexions VCS sur **main** et le dossier Terraform de chaque workspace : `environments/dev/azure`, `environments/dev/ovh`, `environments/staging/azure`, `environments/staging/ovh`, `environments/prod/ovh`. Vérifiez les identifiants cloud existants et la clé SSH de chacun.
- Désactivez les deux options **Auto-apply** et l'auto-destroy dans ces workspaces. Activez **Allow destroy plans** sur les quatre workspaces dev et staging si les bascules sont autorisées.

## Hypothèses et bascule

La comparaison utilise un mois de **730 h** aux tarifs publics HT, sans crédits, quotas gratuits, engagements ou remises. Elle exclut le trafic et les opérations variables. Azure inclut trois VM et leurs disques système, un disque de données, un load balancer et son IP publique. OVH inclut trois C3-4, leurs 150 Go de stockage local, 10 Go de stockage Classic, un load balancer Small et deux Floating IP. Les codes de stockage OVH doivent correspondre à un prix par Go et par heure. Une couverture incomplète arrête la pipeline. Mettez à jour le modèle OVH si la topologie du staging change.

Le workflow sérialise les promotions et vérifie l'état des deux clouds. Pour une bascule, cochez **`allow_switch`** uniquement si vous acceptez de supprimer l'ancien environnement, y compris son disque PostgreSQL. Le workflow valide un plan du nouveau cloud, détruit l'ancien et vérifie que son état est vide avant d'appliquer le nouveau. Il n'y a pas de migration des données. Évitez les applies manuels concurrents. Après un apply échoué, vérifiez aussi les ressources orphelines côté cloud avant de reprendre. Les plans VCS en attente peuvent être écartés par la pipeline pour libérer la file HCP. Les politiques HCP restent appliquées.

Si HCP ne dispose pas d'une version VCS issue de main dont les fichiers correspondent à la révision GitHub, le workflow s'arrête. Initialisez le workspace VCS et vérifiez les filtres de chemins avant de réessayer.
