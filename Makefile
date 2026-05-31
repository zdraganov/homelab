SHELL := /bin/bash
.DEFAULT_GOAL := help

include config.mk

# --- Help ---
.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# --- Secrets ---
.PHONY: secrets-init
secrets-init: ## Generate a new age keypair for SOPS
	@mkdir -p secrets
	@age-keygen -o secrets/age.key 2>&1 | tee /dev/stderr | \
		grep "public key" | awk '{print $$NF}' | \
		xargs -I{} echo "\n→ Update .sops.yaml with public key: {}"
	@echo "⚠  NEVER commit secrets/age.key — it's in .gitignore"

.PHONY: encrypt
encrypt: ## Encrypt a file with SOPS (usage: make encrypt FILE=secrets/foo.enc.yaml)
	@test -n "$(FILE)" || (echo "Usage: make encrypt FILE=path/to/file.enc.yaml" && exit 1)
	sops --encrypt --in-place $(FILE)

.PHONY: decrypt
decrypt: ## Decrypt a file with SOPS (usage: make decrypt FILE=secrets/foo.enc.yaml)
	@test -n "$(FILE)" || (echo "Usage: make decrypt FILE=path/to/file.enc.yaml" && exit 1)
	sops --decrypt $(FILE)

.PHONY: edit-secret
edit-secret: ## Edit an encrypted file in $EDITOR (usage: make edit-secret FILE=secrets/foo.enc.yaml)
	@test -n "$(FILE)" || (echo "Usage: make edit-secret FILE=path/to/file.enc.yaml" && exit 1)
	sops $(FILE)

.PHONY: decrypt-file
decrypt-file: ## Decrypt to .dec.yaml for editing (usage: make decrypt-file FILE=secrets/foo.enc.yaml)
	@test -n "$(FILE)" || (echo "Usage: make decrypt-file FILE=path/to/file.enc.yaml" && exit 1)
	@sops --decrypt $(FILE) > $(subst .enc.,.dec.,$(FILE))
	@echo "→ $(subst .enc.,.dec.,$(FILE)) (gitignored)"

.PHONY: encrypt-file
encrypt-file: ## Encrypt from .dec.yaml back (usage: make encrypt-file FILE=secrets/foo.dec.yaml)
	@test -n "$(FILE)" || (echo "Usage: make encrypt-file FILE=path/to/file.dec.yaml" && exit 1)
	@cp $(FILE) $(subst .dec.,.enc.,$(FILE))
	@sops --encrypt --in-place $(subst .dec.,.enc.,$(FILE))
	@echo "→ $(subst .dec.,.enc.,$(FILE)) encrypted"

# --- Infrastructure (Terraform) ---
TF          := cd terraform && terraform
TF_TOKEN    = $(shell SOPS_AGE_KEY_FILE=secrets/age.key sops --decrypt secrets/proxmox.enc.yaml | grep PROXMOX_API_TOKEN | sed 's/PROXMOX_API_TOKEN: //')

.PHONY: tf-init
tf-init: ## Initialize Terraform
	@$(TF) init

.PHONY: tf-plan
tf-plan: ## Plan infrastructure changes
	@$(TF) plan -var="proxmox_api_token=$(TF_TOKEN)"

.PHONY: tf-apply
tf-apply: ## Apply infrastructure changes
	@$(TF) apply -var="proxmox_api_token=$(TF_TOKEN)"

.PHONY: tf-import
tf-import: ## Import existing resource (usage: make tf-import RES=... ID=pve/101)
	@test -n "$(RES)" || (echo "Usage: make tf-import RES=<resource> ID=<proxmox-id>" && exit 1)
	@test -n "$(ID)" || (echo "Usage: make tf-import RES=<resource> ID=<proxmox-id>" && exit 1)
	@$(TF) import -var="proxmox_api_token=$(TF_TOKEN)" '$(RES)' '$(ID)'

# --- Stacks ---
.PHONY: sync
sync: ## Sync stacks to Dockge LXC (usage: make sync or make sync STACK=proxy)
	@if [ -n "$(STACK)" ]; then \
		$(SSH) "pct exec $(DOCKGE_LXC) -- mkdir -p /opt/stacks/$(STACK)"; \
		cat stacks/$(STACK)/compose.yaml | $(SSH) "pct push $(DOCKGE_LXC) /dev/stdin /opt/stacks/$(STACK)/compose.yaml"; \
		if [ -f stacks/$(STACK)/Caddyfile ]; then \
			cat stacks/$(STACK)/Caddyfile | $(SSH) "pct push $(DOCKGE_LXC) /dev/stdin /opt/stacks/$(STACK)/Caddyfile"; \
		fi; \
	else \
		for dir in stacks/*/; do \
			stack=$$(basename $$dir); \
			[ "$$stack" = "dockge" ] && continue; \
			$(SSH) "pct exec $(DOCKGE_LXC) -- mkdir -p /opt/stacks/$$stack"; \
			cat $$dir/compose.yaml | $(SSH) "pct push $(DOCKGE_LXC) /dev/stdin /opt/stacks/$$stack/compose.yaml"; \
			if [ -f $$dir/Caddyfile ]; then \
				cat $$dir/Caddyfile | $(SSH) "pct push $(DOCKGE_LXC) /dev/stdin /opt/stacks/$$stack/Caddyfile"; \
			fi; \
		done; \
	fi
	@echo "✓ Synced to LXC $(DOCKGE_LXC)"

.PHONY: sync-secrets
sync-secrets: ## Decrypt and sync .env to Dockge LXC (usage: make sync-secrets STACK=proxy)
	@test -n "$(STACK)" || (echo "Usage: make sync-secrets STACK=name" && exit 1)
	@sops --decrypt --output-type dotenv secrets/$(STACK).enc.yaml > /tmp/.env.$(STACK)
	@cat /tmp/.env.$(STACK) | $(SSH) "pct push $(DOCKGE_LXC) /dev/stdin /opt/stacks/$(STACK)/.env"
	@rm -f /tmp/.env.$(STACK)
	@echo "✓ Secrets deployed for $(STACK)"

.PHONY: deploy
deploy: ## Sync and restart a stack on the host (usage: make deploy STACK=proxy)
	@test -n "$(STACK)" || (echo "Usage: make deploy STACK=name" && exit 1)
	@$(MAKE) sync STACK=$(STACK)
	@if [ -f secrets/$(STACK).enc.yaml ]; then $(MAKE) sync-secrets STACK=$(STACK); fi
	@$(SSH) "pct exec $(DOCKGE_LXC) -- bash -c 'cd /opt/stacks/$(STACK) && docker compose up -d'"
	@echo "✓ $(STACK) deployed"

.PHONY: redeploy
redeploy: ## Sync compose, pull latest images and restart a stack (usage: make redeploy STACK=mariya-salon)
	@test -n "$(STACK)" || (echo "Usage: make redeploy STACK=name" && exit 1)
	@$(MAKE) sync STACK=$(STACK)
	@if [ -f secrets/$(STACK).enc.yaml ]; then $(MAKE) sync-secrets STACK=$(STACK); fi
	@$(SSH) "pct exec $(DOCKGE_LXC) -- bash -c 'cd /opt/stacks/$(STACK) && docker compose pull && docker compose up -d --remove-orphans'"
	@echo "✓ $(STACK) redeployed with latest images"

.PHONY: setup-docker-auth
setup-docker-auth: ## Configure ghcr.io credentials on the Dockge LXC from secrets/github.enc.yaml
	@TOKEN=$$(SOPS_AGE_KEY_FILE=secrets/age.key sops --decrypt secrets/github.enc.yaml | grep GITHUB_TOKEN | sed 's/GITHUB_TOKEN: //'); \
	USER=$$(SOPS_AGE_KEY_FILE=secrets/age.key sops --decrypt secrets/github.enc.yaml | grep GITHUB_USER | sed 's/GITHUB_USER: //'); \
	$(SSH) "pct exec $(DOCKGE_LXC) -- bash -c 'echo '\"$$TOKEN\"' | docker login ghcr.io -u '\"$$USER\"' --password-stdin'"
	@echo "✓ ghcr.io credentials configured"

# --- Router (OpenWrt) ---
# Router config is managed from router/Makefile
# Run: cd router && make apply
# Or use these shortcuts:
.PHONY: router-apply router-show dns-apply dns-show
router-apply: ## Apply DNS + port forwarding to OpenWrt (delegates to router/Makefile)
	@$(MAKE) -C $(dir $(abspath $(lastword $(MAKEFILE_LIST))))router apply

router-show: ## Show current router config (delegates to router/Makefile)
	@$(MAKE) -C $(dir $(abspath $(lastword $(MAKEFILE_LIST))))router show

dns-apply: router-apply
dns-show: router-show
.PHONY: status
status: ## Show live status of all VMs and LXCs
	@echo "\033[36mVMs:\033[0m"
	@$(SSH) "qm list"
	@echo "\n\033[36mLXC:\033[0m"
	@$(SSH) "pct list"

.PHONY: shell
shell: ## Open shell into a LXC (usage: make shell ID=104)
	@test -n "$(ID)" || (echo "Usage: make shell ID=<lxc-id>" && exit 1)
	@$(SSH) -t "pct enter $(ID)"

.PHONY: exec
exec: ## Run a command in a LXC (usage: make exec ID=104 CMD="docker ps")
	@test -n "$(ID)" || (echo "Usage: make exec ID=<lxc-id> CMD=\"command\"" && exit 1)
	@test -n "$(CMD)" || (echo "Usage: make exec ID=<lxc-id> CMD=\"command\"" && exit 1)
	@$(SSH) "pct exec $(ID) -- $(CMD)"

# --- Validation ---
.PHONY: lint
lint: ## Validate YAML and Terraform files
	@cd terraform && terraform validate
	@find . -name '*.yaml' -o -name '*.yml' | grep -v '.sops.yaml' | \
		xargs -I{} sh -c 'python3 -c "import yaml; yaml.safe_load(open(\"{}\"))" 2>&1 && echo "✓ {}" || echo "✗ {}"'

.PHONY: check-secrets
check-secrets: ## Verify no plaintext secrets are committed
	@echo "Checking for potential secrets in tracked files..."
	@git grep -l -i "password\|secret\|api_key\|token" -- ':!Makefile' ':!*.md' ':!.sops.yaml' || echo "✓ No plaintext secrets found"
