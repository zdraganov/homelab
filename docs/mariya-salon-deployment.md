# Mariya Salon Deployment

## Overview

`mdraganova.work` is a Next.js app plus Postgres running as the `mariya-salon` Docker stack on the
**Dockge LXC (104, `10.66.1.142`)**. Ingress is **Caddy** (the `proxy` stack on the same LXC) — there is
no Nginx Proxy Manager. TLS is issued via the Cloudflare DNS-01 challenge, so nothing needs to be clicked
in a UI to add or renew a certificate.

Request path:

```
Internet :443 → OpenWrt DNAT (router/port-forwards.yaml) → 10.66.1.142
              → Caddy (stacks/proxy/Caddyfile)
                  /uploads/*  → static file_server from /mnt/mariya-salon
                  everything  → dockge.lan:3010 (app container)
```

`www.mdraganova.work` is a permanent redirect to the apex.

## Stack services

Defined in [../stacks/mariya-salon/compose.yaml](../stacks/mariya-salon/compose.yaml):

| Service | Purpose |
| --- | --- |
| `db` | `postgres:16-alpine`, data in the `db-data` volume, gated by a `pg_isready` healthcheck |
| `migrate` | One-shot `ghcr.io/zdraganov/mariya_salon:migrate`; `app` waits for it to complete successfully |
| `app` | `ghcr.io/zdraganov/mariya_salon:latest`, published on `3010` |
| `backup` | crond running `pg_dump` daily at 02:00 into `/mnt/mariya-salon/backups`, pruning dumps older than 7 days |
| `cron` | crond calling `POST /api/admin/sync-calendar` every 5 min with the `x-sync-secret` header |

## Images

Both images are built and pushed by GitHub Actions in the **`mariya_salon` application repo** on every
push to `main` — nothing is built from this repo. Trigger a manual build from
**Actions → Build & Push Docker Image → Run workflow** in the GitHub UI.

Because the tags (`:latest`, `:migrate`) are mutable, a new build needs a **pull**, not just a restart:

```bash
cd stacks/mariya-salon && make redeploy     # sync + secrets + docker compose pull + up -d
```

Pulling from `ghcr.io` requires the LXC to be logged in. If a pull fails with `denied`/`unauthorized`:

```bash
make setup-docker-auth      # from the repo root; uses secrets/github.enc.yaml
```

## Day-to-day commands

Run from [../stacks/mariya-salon/](../stacks/mariya-salon/) (these wrap the root Makefile):

```bash
make deploy           # sync compose + .env, docker compose up -d (no image pull)
make redeploy         # as above, plus docker compose pull
make logs             # tail the app container
make sync-calendar    # trigger a Google Calendar sync immediately
make backup-now       # one-off timestamped pg_dump alongside the nightly ones
make cleanup-uploads  # delete upload files not referenced by any galleryImage row
make seed-prod        # run the app repo's prisma/seed.ts against production
```

Two of these depend on things outside the stack directory:

- `seed-prod` reads `../mariya_salon/prisma/seed.ts`, so the **application repo must be checked out as a
  sibling of this repo**.
- `cleanup-uploads` pushes [../stacks/mariya-salon/cleanup-uploads.js](../stacks/mariya-salon/cleanup-uploads.js)
  to the LXC itself — `make sync` only ever copies `compose.yaml` and `Caddyfile`, so that script never
  arrives via a normal deploy.

Both run inside a throwaway container on the `mariya-salon_default` network using the `:migrate` image,
which is the one that carries Prisma.

## Secrets

Managed with SOPS in `secrets/mariya-salon.enc.yaml`. Every top-level key in that file becomes a line in
`/opt/stacks/mariya-salon/.env`, which the `app` service loads via `env_file` and compose uses for
`${...}` substitution in the other services. Adding a variable to the app means adding it here — there is
no other source of environment.

Current keys cover Postgres (`POSTGRES_*`, `DATABASE_URL`), admin auth, Resend email, ntfy notifications,
Cloudflare Turnstile, the Google service account used for calendar sync, and `CALENDAR_SYNC_SECRET`
(shared between the `cron` service and the app's sync endpoint).

```bash
make edit-secret FILE=secrets/mariya-salon.enc.yaml   # edit + re-encrypt
cd stacks/mariya-salon && make deploy                 # push the new .env and restart
```

## Uploads and backups

User uploads are **not** in a Docker volume — they live on the LXC filesystem at
`/mnt/mariya-salon/uploads`, bind-mounted into the app at `/app/public/uploads` and also mounted
read-only into Caddy so images are served as static files without touching Next.js.
Nightly database dumps land next to them in `/mnt/mariya-salon/backups`.

`/mnt/mariya-salon` comes from a Proxmox mount point on LXC 104 that is **configured by hand on the host,
not by Terraform** — [../terraform/lxc.tf](../terraform/lxc.tf) records it only as a comment, because the
container's `mount_point` is in `ignore_changes`. Rebuilding the container will not recreate it.

Copy the uploads off the host with:

```bash
make exec ID=104 CMD="tar czf /tmp/uploads.tar.gz -C /mnt/mariya-salon uploads"
```

## Adding or changing the public hostname

A hostname change touches three places and needs two applies:

1. [../stacks/proxy/Caddyfile](../stacks/proxy/Caddyfile) — the site block.
2. `DOMAINS` (and the `PROXIED` expression) in [../stacks/proxy/compose.yaml](../stacks/proxy/compose.yaml) — so DDNS keeps the record current.
3. [../router/port-forwards.yaml](../router/port-forwards.yaml) — only if a new port is involved.

```bash
make deploy STACK=proxy
make router-apply          # only if port forwards changed
```

## Zero Trust: /admin and the MCP portal

Cloudflare Access sits in front of `/admin` and `/api/admin` (Google login, an email allow-list), and
an **MCP server portal** at `mcp.mdraganova.work` lets AI assistants (Claude.ai, ChatGPT, Claude Code)
use the salon's admin panel through the same login. The portal is Cloudflare's OAuth server: the
assistant is sent through Google and the allow-list, and the portal then calls the app's `/api/mcp`
with the app's `MCP_SECRET` as a bearer token. The app never implements OAuth.

All of it is Terraform in `terraform/cloudflare/` (module `terraform/modules/zero-trust/`), a second
root next to the Proxmox one with its own local state.

### Inputs

| Value | Where | Read by |
|---|---|---|
| `CLOUDFLARE_API_TOKEN` | `secrets/terraform-cloudflare.enc.yaml` | `make cf-*` → provider |
| `MCP_SECRET` | `secrets/mariya-salon.enc.yaml` (the app's `.env`) | the app; `make cf-*` → `TF_VAR_mcp_secret` |
| `account_id`, `zone_id`, `admin_emails` | `terraform/cloudflare/terraform.tfvars`, committed | Terraform, and the import targets |

The token is a new one, created at <https://dash.cloudflare.com/profile/api-tokens> with:

- Account → Access: Apps and Policies → Edit
- Account → Access: Organizations, Identity Providers, and Groups → Read
- Account → MCP Portals → Write (covers both the portal and the upstream server registration)
- Zone → DNS → Edit, scoped to `mdraganova.work`

```bash
make edit-secret FILE=secrets/terraform-cloudflare.enc.yaml   # CLOUDFLARE_API_TOKEN: "..."
make edit-secret FILE=secrets/mariya-salon.enc.yaml           # add MCP_SECRET: "<openssl rand -hex 32>"
cd stacks/mariya-salon && make deploy                         # the app needs the secret too
```

### First run

1. Fill in `terraform/cloudflare/terraform.tfvars` (account id, zone id, emails).
2. Adopt the existing `/admin` application so it is updated rather than duplicated. Its id is the
   last segment of its URL in Zero Trust → Access controls → Applications:

   ```bash
   make cf-init
   make cf-import-admin APP_ID=<id>
   ```

3. `make cf-plan`. Expect the imported application to show an in-place update: its dashboard policy
   is replaced by the reusable `Salon admins` policy and `/api/admin` is added as a second
   destination. Read the diff before applying — it is where a field the dashboard set and the
   configuration does not would show up.
4. `make cf-apply`.

If the apply fails creating the portal's Access application because one already exists on
`mcp.mdraganova.work`, Cloudflare created it alongside the portal (the dashboard does; the API
may). Adopt it and apply again:

```bash
make cf-import-portal-app APP_ID=<id of the auto-created application>
make cf-apply
```

### Connecting an assistant

`make cf-output` prints `mcp_portal_url`, `https://mcp.mdraganova.work/mcp`. Paste it into
Claude.ai (Settings → Connectors → Add custom connector) or ChatGPT (Settings → Connectors), or run
`claude mcp add --transport http salon https://mcp.mdraganova.work/mcp`. Each opens a Google login
the first time; only `admin_emails` get in. Tools arrive prefixed with the server id, e.g.
`salon_get_overview`.
