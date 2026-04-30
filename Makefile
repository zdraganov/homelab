SHELL := /bin/bash
.DEFAULT_GOAL := help

SOPS_AGE_KEY_FILE ?= secrets/age.key
export SOPS_AGE_KEY_FILE

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

# --- Stacks ---
.PHONY: stack-up
stack-up: ## Deploy a stack (usage: make stack-up STACK=whoami)
	@test -n "$(STACK)" || (echo "Usage: make stack-up STACK=name" && exit 1)
	docker compose -f stacks/$(STACK)/compose.yaml up -d

.PHONY: stack-down
stack-down: ## Stop a stack (usage: make stack-down STACK=whoami)
	@test -n "$(STACK)" || (echo "Usage: make stack-down STACK=name" && exit 1)
	docker compose -f stacks/$(STACK)/compose.yaml down

.PHONY: stack-logs
stack-logs: ## Tail logs for a stack (usage: make stack-logs STACK=whoami)
	@test -n "$(STACK)" || (echo "Usage: make stack-logs STACK=name" && exit 1)
	docker compose -f stacks/$(STACK)/compose.yaml logs -f

.PHONY: stack-ps
stack-ps: ## Show status of all stacks
	@for dir in stacks/*/; do \
		stack=$$(basename $$dir); \
		echo "\n\033[36m$$stack:\033[0m"; \
		docker compose -f $$dir/compose.yaml ps --format "table {{.Name}}\t{{.Status}}" 2>/dev/null || echo "  not running"; \
	done

# --- Deploy / Sync ---
PVE_HOST    ?= root@pve.lan
DOCKGE_LXC  ?= 104
SSH_KEY     ?= ~/.ssh/homelab_rsa
SSH         := ssh -i $(SSH_KEY) $(PVE_HOST)

.PHONY: sync
sync: ## Sync stacks to Dockge LXC (usage: make sync or make sync STACK=proxy)
	@if [ -n "$(STACK)" ]; then \
		$(SSH) "pct exec $(DOCKGE_LXC) -- mkdir -p /opt/stacks/$(STACK)"; \
		cat stacks/$(STACK)/compose.yaml | $(SSH) "pct push $(DOCKGE_LXC) /dev/stdin /opt/stacks/$(STACK)/compose.yaml"; \
	else \
		for dir in stacks/*/; do \
			stack=$$(basename $$dir); \
			$(SSH) "pct exec $(DOCKGE_LXC) -- mkdir -p /opt/stacks/$$stack"; \
			cat $$dir/compose.yaml | $(SSH) "pct push $(DOCKGE_LXC) /dev/stdin /opt/stacks/$$stack/compose.yaml"; \
		done; \
	fi
	@echo "✓ Synced to LXC $(DOCKGE_LXC)"

.PHONY: sync-secrets
sync-secrets: ## Decrypt and sync .env to Dockge LXC (usage: make sync-secrets STACK=proxy)
	@test -n "$(STACK)" || (echo "Usage: make sync-secrets STACK=name" && exit 1)
	@sops --decrypt secrets/$(STACK).enc.yaml | grep -v '^#' | sed 's/: /=/' > /tmp/.env.$(STACK)
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

# --- Infrastructure ---
.PHONY: inventory
inventory: ## Show infrastructure inventory
	@cat infrastructure/inventory.yaml

# --- Validation ---
.PHONY: lint
lint: ## Validate YAML files
	@find . -name '*.yaml' -o -name '*.yml' | grep -v '.sops.yaml' | \
		xargs -I{} sh -c 'python3 -c "import yaml; yaml.safe_load(open(\"{}\"))" 2>&1 && echo "✓ {}" || echo "✗ {}"'

.PHONY: check-secrets
check-secrets: ## Verify no plaintext secrets are committed
	@echo "Checking for potential secrets in tracked files..."
	@git grep -l -i "password\|secret\|api_key\|token" -- ':!Makefile' ':!*.md' ':!secrets/example.yaml' ':!.sops.yaml' || echo "✓ No plaintext secrets found"
