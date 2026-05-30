# Shared homelab configuration — included by stack Makefiles
PVE_HOST    ?= root@pve.lan
DOCKGE_LXC  ?= 104
SSH_KEY     ?= ~/.ssh/homelab_rsa
SSH         := ssh -i $(SSH_KEY) $(PVE_HOST)

SOPS_AGE_KEY_FILE ?= $(shell git rev-parse --show-toplevel)/secrets/age.key
export SOPS_AGE_KEY_FILE
