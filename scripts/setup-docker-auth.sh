#!/usr/bin/env bash
# Configure ghcr.io credentials inside the Dockge LXC. Runs as root.
# Driven by `make setup-docker-auth` from the repo root.
set -euo pipefail

: "${GHCR_CREDS_FILE:?GHCR_CREDS_FILE is required}"

# Credentials arrive as a file rather than arguments so the token never lands in
# the Proxmox host's process table.
GHCR_USER="$(sed -n '1p' "$GHCR_CREDS_FILE")"
GHCR_TOKEN="$(sed -n '2p' "$GHCR_CREDS_FILE")"
rm -f "$GHCR_CREDS_FILE"

RUNNER_USER="${RUNNER_USER:-github-runner}"

login_as() {
  local user="$1"
  if [ "$user" = "root" ]; then
    printf '%s' "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin
  else
    # docker stores credentials per-user in $HOME/.docker/config.json, so a
    # login as root does nothing for the Actions runner. This is what made
    # deploys fail with "error from registry: unauthorized" while manual pulls
    # over SSH worked fine.
    printf '%s' "$GHCR_TOKEN" | runuser -u "$user" -- docker login ghcr.io -u "$GHCR_USER" --password-stdin
  fi
  echo "  ✓ $user"
}

echo "Logging in to ghcr.io as $GHCR_USER:"
login_as root

if id -u "$RUNNER_USER" >/dev/null 2>&1; then
  login_as "$RUNNER_USER"
else
  echo "  – $RUNNER_USER does not exist yet; skipping (run make runner-install first)"
fi
