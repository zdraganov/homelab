SHELL := /bin/bash
.DEFAULT_GOAL := help

# Inherit homelab SSH config from root
HOMELAB_ROOT := $(shell git rev-parse --show-toplevel)
include $(HOMELAB_ROOT)/config.mk

STACK   := trypost
SECRETS := $(HOMELAB_ROOT)/secrets/$(STACK).enc.yaml
COMPOSE := cd /opt/stacks/$(STACK) && docker compose

.PHONY: help init-secrets deploy redeploy init logs artisan backup-now

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# Every value TryPost needs at boot is generated here so nothing has to be
# pasted by hand. The Passport keys are a plain RSA pair, the same thing
# `php artisan passport:keys` produces; they go in as one line with literal
# "\n" because Passport unescapes that itself and sops' dotenv output keeps
# it intact. Credentials only you can obtain are left empty and listed in
# docs/trypost.md.
init-secrets: ## One-off: create secrets/trypost.enc.yaml with generated keys (refuses to overwrite)
	@test ! -f $(SECRETS) || (echo "$(SECRETS) already exists — use: make edit-secret FILE=secrets/$(STACK).enc.yaml" && exit 1)
	@set -e; \
	TMP=$$(mktemp -d); trap 'rm -rf "$$TMP"' EXIT; \
	openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out "$$TMP/private.pem" 2>/dev/null; \
	openssl pkey -in "$$TMP/private.pem" -pubout -out "$$TMP/public.pem" 2>/dev/null; \
	PRIV=$$(awk 'NF {printf "%s\\n", $$0}' "$$TMP/private.pem"); \
	PUB=$$(awk 'NF {printf "%s\\n", $$0}' "$$TMP/public.pem"); \
	{ \
		echo "# TryPost — every key becomes a line in /opt/stacks/$(STACK)/.env (see docs/trypost.md)"; \
		echo "APP_KEY: 'base64:$$(openssl rand -base64 32)'"; \
		echo "POSTGRES_PASSWORD: '$$(openssl rand -hex 24)'"; \
		echo "REVERB_APP_SECRET: '$$(openssl rand -hex 32)'"; \
		echo "PASSPORT_PRIVATE_KEY: '$$PRIV'"; \
		echo "PASSPORT_PUBLIC_KEY: '$$PUB'"; \
		echo "# Resend SMTP: the API key is the password (https://resend.com/api-keys)"; \
		echo "MAIL_PASSWORD: ''"; \
		echo "MAIL_FROM_ADDRESS: 'me@mdraganova.work'"; \
		echo "# Meta for Developers app — fill in when connecting Facebook / Instagram / Threads"; \
		echo "FACEBOOK_CLIENT_ID: ''"; \
		echo "FACEBOOK_CLIENT_SECRET: ''"; \
		echo "INSTAGRAM_CLIENT_ID: ''"; \
		echo "INSTAGRAM_CLIENT_SECRET: ''"; \
		echo "THREADS_CLIENT_ID: ''"; \
		echo "THREADS_CLIENT_SECRET: ''"; \
		echo "# TikTok for Developers"; \
		echo "TIKTOK_CLIENT_ID: ''"; \
		echo "TIKTOK_CLIENT_SECRET: ''"; \
	} > "$$TMP/$(STACK).enc.yaml"; \
	sops --encrypt --in-place "$$TMP/$(STACK).enc.yaml"; \
	cp "$$TMP/$(STACK).enc.yaml" $(SECRETS)
	@echo "✓ $(SECRETS) created — fill in the empty keys with: make edit-secret FILE=secrets/$(STACK).enc.yaml"

deploy: ## Sync compose + secrets and restart the stack
	@$(MAKE) -C $(HOMELAB_ROOT) deploy STACK=$(STACK)

redeploy: ## Pull the image and restart — run after bumping the tag in compose.yaml
	@$(MAKE) -C $(HOMELAB_ROOT) redeploy STACK=$(STACK)

init: ## First run only: seed plans, the Passport client and the admin user (admin@trypost.it / password)
	@$(SSH) "pct exec $(DOCKGE_LXC) -- bash -c '$(COMPOSE) exec app php artisan db:seed --force && $(COMPOSE) exec app php artisan db:seed --class=UserSeeder --force'"
	@echo "✓ seeded — log in as admin@trypost.it / password and change the email and password straight away"

logs: ## Tail app logs (nginx, php-fpm, horizon, reverb, scheduler all log here)
	@$(SSH) "pct exec $(DOCKGE_LXC) -- bash -c '$(COMPOSE) logs -f app'"

artisan: ## Run an artisan command in the app container (usage: make artisan CMD="horizon:status")
	@test -n "$(CMD)" || (echo 'Usage: make artisan CMD="horizon:status"' && exit 1)
	@$(SSH) -t "pct exec $(DOCKGE_LXC) -- bash -c '$(COMPOSE) exec app php artisan $(CMD)'"

backup-now: ## Trigger an immediate database backup (alongside the nightly ones)
	@$(SSH) "pct exec $(DOCKGE_LXC) -- bash -c '$(COMPOSE) exec backup sh -c \"pg_dump -h pgsql -U trypost trypost | gzip > /backups/trypost-\$$(date +%Y%m%d-%H%M%S)-manual.sql.gz && echo done\"'"
	@echo "✓ Backup complete"
