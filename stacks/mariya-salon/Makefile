SHELL := /bin/bash
.DEFAULT_GOAL := help

# Inherit homelab SSH config from root
HOMELAB_ROOT := $(shell git rev-parse --show-toplevel)
include $(HOMELAB_ROOT)/config.mk

STACK := mariya-salon

.PHONY: help deploy redeploy logs sync-calendar seed-prod

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

deploy: ## Sync compose + secrets and restart the stack
	@$(MAKE) -C $(HOMELAB_ROOT) deploy STACK=$(STACK)

redeploy: ## Pull latest images and restart the stack
	@$(MAKE) -C $(HOMELAB_ROOT) redeploy STACK=$(STACK)

logs: ## Tail app logs
	@$(SSH) "pct exec $(DOCKGE_LXC) -- bash -c 'cd /opt/stacks/$(STACK) && docker compose logs -f app'"

sync-calendar: ## Trigger Google Calendar sync on production
	@SECRET=$$(SOPS_AGE_KEY_FILE=$(HOMELAB_ROOT)/secrets/age.key sops --decrypt $(HOMELAB_ROOT)/secrets/$(STACK).enc.yaml | grep CALENDAR_SYNC_SECRET | sed 's/CALENDAR_SYNC_SECRET: //'); \
	$(SSH) "pct exec $(DOCKGE_LXC) -- wget -qO- --header='x-sync-secret: '\"$$SECRET\"'' --post-data='' http://localhost:3010/api/admin/sync-calendar"
	@echo "✓ Calendar sync triggered"

seed-prod: ## Run database seed on production
	@cat $(HOMELAB_ROOT)/../mariya_salon/prisma/seed.ts | $(SSH) "pct push $(DOCKGE_LXC) /dev/stdin /tmp/seed.ts"
	@$(SSH) "pct exec $(DOCKGE_LXC) -- bash -c 'docker run --rm \
		--network $(STACK)_default \
		-v /tmp/seed.ts:/app/prisma/seed.ts \
		--env-file /opt/stacks/$(STACK)/.env \
		ghcr.io/zdraganov/mariya_salon:migrate \
		npx tsx prisma/seed.ts'"
	@echo "✓ Production seed complete"

backup-now: ## Trigger an immediate database backup
	@$(SSH) "pct exec $(DOCKGE_LXC) -- bash -c 'cd /opt/stacks/$(STACK) && docker compose exec backup sh -c \"pg_dump -h db -U \$$POSTGRES_USER \$$POSTGRES_DB | gzip > /backups/mariya-salon-\$$(date +%Y%m%d-%H%M%S)-manual.sql.gz && echo done\"'"
	@echo "✓ Backup complete"
