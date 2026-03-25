.PHONY: init plan apply destroy output fmt validate check save-key \
        ssh tunnel status logs deploy restart stop setup dashboard \
        backup restore push-env kv-set cloud-init-log cloud-init-status \
        teams-configure teams-manifest help

# ─── Config ────────────────────────────────────────────────────────────────
ADMIN_USER ?= openclaw
SSH_KEY    ?= ~/.ssh/openclaw.pem
VM_IP      := $(shell terraform output -raw public_ip 2>/dev/null)

# ─── Terraform ─────────────────────────────────────────────────────────────
init:
	terraform init -upgrade

plan:
	terraform plan

apply:
	terraform apply

destroy:
	@echo "WARNING: This will destroy all resources. Use 'terraform destroy' to confirm."
	@echo "Note: Key Vault has prevent_destroy = true and purge protection enabled."
	terraform destroy

output:
	terraform output

fmt:
	terraform fmt -recursive

validate:
	terraform validate

## Run fmt + validate (use before every commit)
check: fmt validate
	@echo "All checks passed."

## Save the auto-generated SSH private key to disk
save-key:
	@terraform output -raw ssh_private_key > "$(SSH_KEY)" 2>/dev/null \
		&& chmod 600 "$(SSH_KEY)" \
		&& echo "SSH key saved to $(SSH_KEY)" \
		|| echo "No auto-generated key (ssh_public_key was provided in tfvars)"

# ─── SSH & Access ──────────────────────────────────────────────────────────
ssh:
	@echo "Connecting to $(VM_IP)..."
	ssh -i "$(SSH_KEY)" $(ADMIN_USER)@$(VM_IP)

tunnel:
	@echo "Opening SSH tunnel — gateway at http://localhost:18789"
	ssh -N -i "$(SSH_KEY)" -L 18789:127.0.0.1:18789 $(ADMIN_USER)@$(VM_IP)

tunnel-https:
	@echo "SSH tunnel → https://openclaw.local:8443  |  Traefik dashboard → http://localhost:8080"
	ssh -N -i "$(SSH_KEY)" \
		-L 8443:127.0.0.1:443 \
		-L 8080:127.0.0.1:8080 \
		$(ADMIN_USER)@$(VM_IP)

# ─── OpenClaw Management ──────────────────────────────────────────────────
status:
	ssh -i "$(SSH_KEY)" $(ADMIN_USER)@$(VM_IP) 'cd ~/openclaw && docker compose ps'

logs:
	ssh -i "$(SSH_KEY)" $(ADMIN_USER)@$(VM_IP) 'cd ~/openclaw && docker compose logs -f --tail=50'

deploy:
	ssh -i "$(SSH_KEY)" $(ADMIN_USER)@$(VM_IP) 'cd ~/openclaw && docker compose pull && docker compose up -d'

restart:
	ssh -i "$(SSH_KEY)" $(ADMIN_USER)@$(VM_IP) 'cd ~/openclaw && docker compose restart'

stop:
	ssh -i "$(SSH_KEY)" $(ADMIN_USER)@$(VM_IP) 'cd ~/openclaw && docker compose down'

setup:
	@echo "Running OpenClaw interactive setup on VM (onboard + API key + pairing)..."
	ssh -t -i "$(SSH_KEY)" $(ADMIN_USER)@$(VM_IP) 'cd ~/openclaw/repo && bash docker-setup.sh'

dashboard:
	ssh -i "$(SSH_KEY)" $(ADMIN_USER)@$(VM_IP) 'cd ~/openclaw && docker compose run --rm openclaw-cli dashboard --no-open'

## List pending device pairing requests (run after browser shows "pairing required")
pair-list:
	@TOKEN=$$(ssh -i "$(SSH_KEY)" $(ADMIN_USER)@$(VM_IP) 'grep OPENCLAW_GATEWAY_TOKEN ~/openclaw/.env | cut -d= -f2') && \
	ssh -i "$(SSH_KEY)" $(ADMIN_USER)@$(VM_IP) "cd ~/openclaw && docker compose run --rm openclaw-cli devices list --url ws://127.0.0.1:18789 --token $$TOKEN"

## Approve a pending device pairing request (usage: make pair-approve ID=<request-id>)
pair-approve:
	@test -n "$(ID)" || (echo "Usage: make pair-approve ID=<request-id>  (get ID from make pair-list)" && exit 1)
	@TOKEN=$$(ssh -i "$(SSH_KEY)" $(ADMIN_USER)@$(VM_IP) 'grep OPENCLAW_GATEWAY_TOKEN ~/openclaw/.env | cut -d= -f2') && \
	ssh -i "$(SSH_KEY)" $(ADMIN_USER)@$(VM_IP) "cd ~/openclaw && docker compose run --rm openclaw-cli devices approve $(ID) --url ws://127.0.0.1:18789 --token $$TOKEN"

# ─── Backup & Restore ─────────────────────────────────────────────────────
backup:
	@mkdir -p ./backups
	@echo "Creating backup on VM..."
	ssh -i "$(SSH_KEY)" $(ADMIN_USER)@$(VM_IP) \
		'tar czf /tmp/openclaw-backup-$$(date +%Y%m%d-%H%M%S).tar.gz -C /home/$(ADMIN_USER) .openclaw'
	@echo "Downloading backup..."
	scp -i "$(SSH_KEY)" $(ADMIN_USER)@$(VM_IP):'/tmp/openclaw-backup-*.tar.gz' ./backups/
	@echo "Backup saved to ./backups/"

restore:
	@test -n "$(BACKUP)" || (echo "Usage: make restore BACKUP=backups/openclaw-backup-xxx.tar.gz" && exit 1)
	scp -i "$(SSH_KEY)" $(BACKUP) $(ADMIN_USER)@$(VM_IP):/tmp/restore.tar.gz
	ssh -i "$(SSH_KEY)" $(ADMIN_USER)@$(VM_IP) \
		'cd ~/openclaw && docker compose down \
		&& tar xzf /tmp/restore.tar.gz -C /home/$(ADMIN_USER) \
		&& docker compose up -d \
		&& rm /tmp/restore.tar.gz'

# ─── Secrets ──────────────────────────────────────────────────────────────
## Push a local .env.production to the VM (bypasses Key Vault — dev only)
push-env:
	@test -f .env.production || (echo ".env.production not found" && exit 1)
	scp -i "$(SSH_KEY)" .env.production $(ADMIN_USER)@$(VM_IP):~/openclaw/.env
	ssh -i "$(SSH_KEY)" $(ADMIN_USER)@$(VM_IP) 'chmod 600 ~/openclaw/.env'

## Update a secret in Key Vault (usage: make kv-set NAME=anthropic-api-key VALUE=sk-ant-...)
kv-set:
	@test -n "$(NAME)"  || (echo "Usage: make kv-set NAME=<secret-name> VALUE=<value>" && exit 1)
	@test -n "$(VALUE)" || (echo "Usage: make kv-set NAME=<secret-name> VALUE=<value>" && exit 1)
	az keyvault secret set \
		--vault-name "$$(terraform output -raw key_vault_name)" \
		--name "$(NAME)" \
		--value "$(VALUE)"

# ─── Teams ────────────────────────────────────────────────────────────────
## Fix "duplicate plugin id" warning: remove external extension + set plugins.allow = ["msteams"]
## msteams is bundled in OpenClaw — the external extension installed via `plugins install` conflicts
teams-configure:
	@ssh -i "$(SSH_KEY)" $(ADMIN_USER)@$(VM_IP) "cd ~/openclaw && \
		docker compose run --rm --entrypoint sh openclaw-cli -c 'rm -rf ~/.openclaw/extensions/msteams' && \
		docker compose run --rm openclaw-cli config set plugins.allow '[\"msteams\"]' --strict-json && \
		docker compose restart openclaw-gateway"
	@echo "Teams plugin configured. Gateway restarted."

## Generate Teams app package (usage: make teams-manifest)
## Outputs: teams-app.zip — upload via Teams Admin Center or Developer Portal
teams-manifest:
	@mkdir -p ./teams-manifest
	@MS_APP_ID="$$(terraform output -raw teams_ms_app_id 2>/dev/null)" && \
	BOT_DOMAIN="$$(terraform output -raw teams_bot_endpoint 2>/dev/null | sed 's|https://||; s|/api/messages||')" && \
	APP_ID="$$(python3 -c 'import uuid; print(uuid.uuid4())' 2>/dev/null || uuidgen | tr '[:upper:]' '[:lower:]')" && \
	sed "s/{{MS_APP_ID}}/$$MS_APP_ID/g; s/{{TEAMS_BOT_DOMAIN}}/$$BOT_DOMAIN/g; s/{{UNIQUE_APP_ID}}/$$APP_ID/g" \
		./teams-manifest/manifest.json.tftpl > ./teams-manifest/manifest.json && \
	echo "Generated: teams-manifest/manifest.json" && \
	echo "MS_APP_ID  = $$MS_APP_ID" && \
	echo "BOT_DOMAIN = $$BOT_DOMAIN" && \
	echo "APP_ID     = $$APP_ID (unique Teams app ID)" && \
	echo "" && \
	echo "Add color.png (192x192) and outline.png (32x32) to teams-manifest/, then:" && \
	echo "  cd teams-manifest && zip -r ../teams-app.zip manifest.json color.png outline.png"

# ─── Cloud-init debug ────────────────────────────────────────────────────
cloud-init-log:
	ssh -i "$(SSH_KEY)" $(ADMIN_USER)@$(VM_IP) 'sudo tail -100 /var/log/cloud-init-output.log'

cloud-init-status:
	ssh -i "$(SSH_KEY)" $(ADMIN_USER)@$(VM_IP) 'cloud-init status --long'

openclaw-log:
	ssh -i "$(SSH_KEY)" $(ADMIN_USER)@$(VM_IP) 'cat /var/log/openclaw-setup.log'

# ─── Help ────────────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "  terraform-azurerm-openclaw"
	@echo "  ─────────────────────────"
	@echo ""
	@echo "  Infrastructure:"
	@echo "    make init            Initialize Terraform (run once)"
	@echo "    make plan            Preview changes"
	@echo "    make apply           Deploy infrastructure"
	@echo "    make destroy         Tear down (see note on Key Vault)"
	@echo "    make output          Show Terraform outputs"
	@echo "    make check           fmt + validate (run before commits)"
	@echo "    make save-key        Save auto-generated SSH key to ~/.ssh/openclaw.pem"
	@echo ""
	@echo "  Access:"
	@echo "    make ssh             SSH to VM"
	@echo "    make tunnel          SSH tunnel → gateway at localhost:18789"
	@echo ""
	@echo "  OpenClaw:"
	@echo "    make setup           Run interactive OpenClaw setup"
	@echo "    make deploy          Pull latest image & restart"
	@echo "    make status          Show container status"
	@echo "    make logs            Stream gateway logs"
	@echo "    make restart         Restart containers"
	@echo "    make stop            Stop containers"
	@echo "    make dashboard       Get dashboard token URL"
	@echo ""
	@echo "  Data:"
	@echo "    make backup                              Backup .openclaw/ to ./backups/"
	@echo "    make restore BACKUP=backups/file.tar.gz  Restore from backup"
	@echo "    make push-env                            Push .env.production to VM"
	@echo "    make kv-set NAME=<name> VALUE=<val>      Update Key Vault secret"
	@echo ""
	@echo "  Teams:"
	@echo "    make teams-configure              Fix plugins.allow + restart gateway"
	@echo "    make teams-manifest               Generate Teams app package (teams-app.zip)"
	@echo ""
	@echo "  Debug:"
	@echo "    make cloud-init-log     View cloud-init output"
	@echo "    make cloud-init-status  Check cloud-init status"
	@echo "    make openclaw-log       View OpenClaw setup log"
	@echo ""
	@echo "  Variables (override with make VAR=value):"
	@echo "    ADMIN_USER  SSH username (default: openclaw)"
	@echo "    SSH_KEY     Path to private key (default: ~/.ssh/openclaw.pem)"
	@echo ""
