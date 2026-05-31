SHELL := /bin/bash
.DEFAULT_GOAL := help

HOMELAB_ROOT := $(shell git rev-parse --show-toplevel)
include $(HOMELAB_ROOT)/config.mk

OPENWRT_HOST ?= root@openwrt.lan
OPENWRT_SSH  := ssh -i ~/.ssh/homelab_openwrt $(OPENWRT_HOST)

.PHONY: help apply show

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

apply: ## Apply DNS, DHCP and port forwarding config to OpenWrt
	@python3 $(HOMELAB_ROOT)/router/generate.py | $(OPENWRT_SSH) "sh"
	@echo "✓ Router config applied (DNS + port forwards)"

show: ## Show current DNS and port forward rules on OpenWrt
	@echo "\033[36mDHCP/DNS hosts:\033[0m"
	@$(OPENWRT_SSH) "uci show dhcp | grep '@host'"
	@echo "\n\033[36mPort forwards:\033[0m"
	@$(OPENWRT_SSH) "uci show firewall | grep -E 'redirect|dest_ip|dest_port|src_dport|\.name' | grep -v '^firewall\.@rule'"
