#!/usr/bin/env bash
# Stop, uninstall and deregister the Actions runner. Runs INSIDE the Dockge LXC
# as root. Driven by `make runner-remove` — see docs/actions-runner.md.
set -euo pipefail

: "${RUNNER_TOKEN_FILE:?RUNNER_TOKEN_FILE is required}"
RUNNER_USER="${RUNNER_USER:-github-runner}"
RUNNER_DIR="${RUNNER_DIR:-/opt/actions-runner}"

RUNNER_TOKEN="$(cat "$RUNNER_TOKEN_FILE")"
rm -f "$RUNNER_TOKEN_FILE"

if [ ! -d "$RUNNER_DIR" ]; then
  echo "No runner installed at $RUNNER_DIR — nothing to do."
  exit 0
fi

cd "$RUNNER_DIR"
./svc.sh stop || true
./svc.sh uninstall || true

# Deregister from GitHub before deleting the directory, otherwise the repo keeps
# an offline runner entry that has to be removed by hand in the UI.
runuser -u "$RUNNER_USER" -- ./config.sh remove --token "$RUNNER_TOKEN" || true

cd /
rm -rf "$RUNNER_DIR"
echo "✓ runner removed (user '$RUNNER_USER' left in place)"
