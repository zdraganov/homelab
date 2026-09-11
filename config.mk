# Shared homelab configuration — included by stack Makefiles
PVE_HOST    ?= root@pve.lan
DOCKGE_LXC  ?= 104
# The private half lives in the Bitwarden desktop app's SSH agent, not on disk.
# Pointing ssh at the *public* key file makes it ask the agent for exactly that
# key — the same effect as a private key path, without the "identity file not
# accessible" warning a missing one produces.
SSH_KEY     ?= ~/.ssh/homelab.pub
SSH         := ssh -i $(SSH_KEY) $(PVE_HOST)

SOPS_AGE_KEY_FILE ?= $(shell git rev-parse --show-toplevel)/secrets/age.key
export SOPS_AGE_KEY_FILE
