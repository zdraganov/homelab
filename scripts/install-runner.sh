#!/usr/bin/env bash
# Install a GitHub Actions self-hosted runner. Runs INSIDE the Dockge LXC as root.
# Driven by `make runner-install` from the repo root — see docs/actions-runner.md.
set -euo pipefail

: "${RUNNER_URL:?RUNNER_URL is required}"
: "${RUNNER_VERSION:?RUNNER_VERSION is required}"
: "${RUNNER_SHA256:?RUNNER_SHA256 is required}"
: "${RUNNER_TOKEN_FILE:?RUNNER_TOKEN_FILE is required}"
RUNNER_NAME="${RUNNER_NAME:-dockge}"
RUNNER_LABELS="${RUNNER_LABELS:-self-hosted,homelab,dockge}"
RUNNER_USER="${RUNNER_USER:-github-runner}"
RUNNER_DIR="${RUNNER_DIR:-/opt/actions-runner}"

# The registration token arrives as a file rather than an argument so it never
# lands in the Proxmox host's process table. It is single-use and short-lived.
RUNNER_TOKEN="$(cat "$RUNNER_TOKEN_FILE")"
rm -f "$RUNNER_TOKEN_FILE"

command -v curl >/dev/null || { apt-get update -qq && apt-get install -y -qq curl; }

# config.sh refuses to run as root, and running CI as root on a privileged
# container is a poor trade regardless. Note that docker group membership is
# still root-equivalent — docs/actions-runner.md covers what that does and
# does not buy us.
id -u "$RUNNER_USER" >/dev/null 2>&1 || useradd --create-home --shell /bin/bash "$RUNNER_USER"
usermod -aG docker "$RUNNER_USER"

# A re-run must stop the old service before the directory is replaced.
if [ -x "$RUNNER_DIR/svc.sh" ]; then
  ( cd "$RUNNER_DIR" && ./svc.sh stop || true; ./svc.sh uninstall || true )
fi

mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

tarball="actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
curl -fsSL -o "$tarball" \
  "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${tarball}"
echo "${RUNNER_SHA256}  ${tarball}" | sha256sum -c -
tar xzf "$tarball"
rm -f "$tarball"

# The runner is a .NET app and will not start without libicu et al.
./bin/installdependencies.sh

chown -R "$RUNNER_USER":"$RUNNER_USER" "$RUNNER_DIR"

# --replace lets a re-run take over the same runner name instead of leaving a
# dead entry behind in the repo's runner list.
runuser -u "$RUNNER_USER" -- ./config.sh \
  --url "$RUNNER_URL" \
  --token "$RUNNER_TOKEN" \
  --name "$RUNNER_NAME" \
  --labels "$RUNNER_LABELS" \
  --work _work \
  --unattended --replace

./svc.sh install "$RUNNER_USER"
./svc.sh start
./svc.sh status || true
