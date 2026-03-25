# TODO — Teams Integration

## Prérequis manuels (hors Terraform)

- [ ] **Azure AD App Registration** — portal.azure.com → App registrations → New registration
  - Copier l'Application (client) ID → `ms_app_id`
  - Créer un client secret → `ms_app_password` (ou `export TF_VAR_ms_app_password="..."`)

- [ ] **Domaine public** pointé sur l'IP de la VM
  - Exemple : `openclaw.example.com` → `teams_bot_domain`
  - TLS Let's Encrypt automatique via Traefik si `teams_acme_email` est fourni

## Déploiement

- [ ] Remplir `terraform.tfvars` :
  ```hcl
  enable_teams     = true
  ms_app_id        = "<client-id>"
  teams_bot_domain = "openclaw.example.com"
  teams_acme_email = "admin@example.com"
  ```
- [ ] `export TF_VAR_ms_app_password="<client-secret>"`
- [ ] `make apply` → crée l'Azure Bot + Teams channel + NSG 80/443 + Traefik ACME

## Package Teams

- [ ] `make teams-manifest` → génère `teams-manifest/manifest.json`
- [ ] Ajouter `color.png` (192×192) et `outline.png` (32×32) dans `teams-manifest/`
- [ ] `cd teams-manifest && zip -r ../teams-app.zip manifest.json color.png outline.png`
- [ ] Uploader `teams-app.zip` dans Teams Admin Center ou Developer Portal

## Tests

- [ ] **Valider le nouveau cloud-init** avec la VM de test (`test.tf` déjà prêt)
  ```bash
  terraform apply -target=azurerm_public_ip.test -target=azurerm_network_interface.test \
    -target=azurerm_linux_virtual_machine.test -target=azurerm_role_assignment.test_kv_secrets_user
  # vérifier logs, puis :
  terraform destroy -target=azurerm_linux_virtual_machine.test \
    -target=azurerm_role_assignment.test_kv_secrets_user \
    -target=azurerm_network_interface.test -target=azurerm_public_ip.test
  # puis : rm test.tf
  ```

## Optionnel / améliorations futures

- [ ] Passer le Bot SKU de `F0` (gratuit) à `S1` si > 10 000 messages/mois (modifier `teams.tf`)
- [ ] Ajouter le provider `azuread` pour créer l'App Registration via Terraform
- [ ] Azure Monitor / Log Analytics sur le Key Vault (`azurerm_monitor_diagnostic_setting`)
- [ ] Azure Backup pour la VM (`azurerm_backup_protected_vm`)
- [ ] Let's Encrypt sans domaine : remplacer par Azure Application Gateway ou ngrok pour les tests
