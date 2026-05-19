# Mariya Salon Deployment

## Overview

The salon app runs as a Docker stack on the Dockge LXC, exposed via Nginx Proxy Manager at `mdraganova.work`.

## Prerequisites

1. **Cloudflare DNS** — `mdraganova.work` A record pointing to your homelab IP (handled by DDNS in the proxy stack)
2. **Docker image** — build and push to `ghcr.io/zdraganov/mariya-salon:latest` (see below)
3. **Nginx Proxy Manager** — proxy host configured for the domain

## Build & Push Docker Image

The image is built automatically via GitHub Actions on every push to `main`.
It's published to `ghcr.io/zdraganov/mariya_salon:latest`.

To trigger a manual build, go to **Actions → Build & Push Docker Image → Run workflow** in the GitHub UI.

To pull the latest image on the homelab server:

```bash
make exec ID=104 CMD="cd /opt/stacks/mariya-salon && docker compose pull && docker compose up -d"
```

## Deploy

```bash
# From the homelab directory
make deploy STACK=mariya-salon

# Also redeploy proxy stack to pick up the new DDNS domain
make deploy STACK=proxy
```

## Nginx Proxy Manager Setup

In the NPM UI (`http://<homelab-ip>:81`):

1. **Add Proxy Host**
   - Domain: `mdraganova.work`
   - Scheme: `http`
   - Forward Hostname: `<dockge-lxc-ip>` (e.g. `192.168.1.104`)
   - Forward Port: `3010`
   - Enable: Websockets Support (for Next.js hot reload)

2. **SSL Certificate**
   - Request a Let's Encrypt certificate for `mdraganova.work`
   - Enable "Force SSL" and "HTTP/2 Support"

## Secrets

Secrets are managed via SOPS. To edit:

```bash
make edit-secret FILE=secrets/mariya-salon.enc.yaml
```

To redeploy after secret changes:

```bash
make sync-secrets STACK=mariya-salon
make exec ID=104 CMD="cd /opt/stacks/mariya-salon && docker compose up -d"
```

## Uploads Persistence

The `uploads` volume persists user-uploaded images. To back up:

```bash
make exec ID=104 CMD="docker run --rm -v mariya-salon_uploads:/data -v /tmp:/backup alpine tar czf /backup/uploads.tar.gz /data"
```
