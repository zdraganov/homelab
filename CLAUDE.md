# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Declarative source of truth for a single-node Proxmox homelab (`pve.lan`, subnet `10.66.1.0/24`).
There is no CI/CD and no agent on the server: **every change is pushed from a workstation by running `make`**.
Editing a file here changes nothing until the matching `make` target runs.

Requires `age`, `sops`, `terraform`, `python3` (with PyYAML), and the SSH keys
`~/.ssh/homelab_rsa` (Proxmox) and `~/.ssh/homelab_openwrt` (router).

## The three control planes

| Plane | Source | Applied by | Target |
| --- | --- | --- | --- |
| Infrastructure (VMs/LXCs) | [terraform/](terraform/) | `make tf-apply` | Proxmox API on `pve.lan:8006` |
| Services (Docker stacks) | [stacks/](stacks/) | `make deploy STACK=x` | `/opt/stacks/<name>` inside LXC 104 |
| Network (DNS/DHCP/NAT) | [router/](router/) | `make router-apply` | OpenWrt via UCI over SSH |

Secrets ([secrets/](secrets/), SOPS + age) cut across all three.

## Everything goes through the Proxmox host

No target is reached directly. `config.mk` defines `SSH := ssh -i ~/.ssh/homelab_rsa root@pve.lan`,
and container work is `pct exec <id>` / `pct push <id>` on the other side of that hop.
When debugging, reproduce the same path: `make exec ID=104 CMD="docker ps"`, not a direct SSH to a container.

## Stack deployment mechanics

All Docker stacks — regardless of purpose — run in **LXC 104 (`dockge`, `10.66.1.142`, alias `dockge.lan` / `proxy.lan`)**.
Dockge is only a web UI over `/opt/stacks`; deploys do not use it.

`make sync STACK=x` pushes **only `compose.yaml` and `Caddyfile`** from `stacks/<x>/` — nothing else.
Any other file a stack needs (e.g. [cleanup-uploads.js](stacks/mariya-salon/cleanup-uploads.js)) must be
pushed explicitly by a dedicated target. `make sync` with no `STACK` loops all stacks and skips `dockge`
(it manages the very directory it would be written into).

`make deploy STACK=x` = sync + push secrets (if `secrets/x.enc.yaml` exists) + `docker compose up -d`.
`make redeploy STACK=x` adds `docker compose pull` and `--remove-orphans` — use it when the image tag is
mutable (`:latest`, `:migrate` on `ghcr.io/zdraganov/*`) and the tag itself did not change.

**Naming is the contract**: the stack directory name, the secrets file basename, and the remote
`/opt/stacks/<name>` directory must all match, or `deploy` silently skips the `.env` step.

Stack-specific operational commands live in nested Makefiles (see [stacks/mariya-salon/Makefile](stacks/mariya-salon/Makefile)),
which `include` the root `config.mk` via `git rev-parse --show-toplevel` so they work from any cwd.

## Secrets

`secrets/<stack>.enc.yaml` is a flat map of `KEY: value`. `sync-secrets` runs
`sops --decrypt --output-type dotenv` and writes the result to `/opt/stacks/<stack>/.env`,
so **every top-level key becomes an env var in that stack's compose file**. Keep the two in sync.

```bash
make edit-secret FILE=secrets/proxy.enc.yaml     # edit in $EDITOR, re-encrypts on save (preferred)
make decrypt-file FILE=secrets/x.enc.yaml        # → x.dec.yaml (gitignored)
make encrypt-file FILE=secrets/x.dec.yaml        # → back to x.enc.yaml
make check-secrets                               # grep tracked files for plaintext leaks
```

`secrets/age.key` is the private key and is gitignored; `.sops.yaml` holds the public key.
`config.mk` exports `SOPS_AGE_KEY_FILE` pointing at it, so `sops` works without env setup — but only
when invoked through `make`. Some targets also set it explicitly because they shell out.

Some secrets files (`plex`, `truenas`, `proxmox`, `github`, `cloudflared`, `immich`) have **no matching stack** —
they feed Terraform, `setup-docker-auth`, or services configured by hand on their own LXC.

## Terraform

State is **local and gitignored** — `terraform/terraform.tfstate` is not shared. Never commit it.
The Proxmox API token is decrypted from `secrets/proxmox.enc.yaml` on every invocation and passed as
`-var="proxmox_api_token=…"`; always go through `make tf-plan` / `make tf-apply`, not bare `terraform`.

Resources are defined as maps in `locals` ([lxc.tf](terraform/lxc.tf), [vms.tf](terraform/vms.tf)) and
expanded with `for_each` — add a container by adding a map entry, not a new resource block.

This infrastructure was **adopted after the fact**, which explains the defensive lifecycle rules:
`prevent_destroy = true` plus broad `ignore_changes` (including `features` and `mount_point`).
Consequence: **some LXC 104 settings are managed manually via SSH and Terraform will not reconcile them** —
notably the `mp0` bind mount `/mnt/pve/MariaSalon/uploads → /mnt/mariya-salon/uploads` and `nesting/keyctl`.
Adding a mount to `lxc.tf` for an existing container is a no-op; do it on the host and comment it in the map.
New resources are adopted with `make tf-import RES=<addr> ID=pve/<vmid>` (see [docs/adopting-existing.md](docs/adopting-existing.md)).

## Router

[router/generate.py](router/generate.py) reads `dns-hosts.yaml`, `dns-aliases.yaml` and `port-forwards.yaml`
and **prints UCI shell commands to stdout**; `make router-apply` pipes them into `sh` on OpenWrt.
Preview any change with `python3 router/generate.py` before applying.

The generated script is **destructive by design**: it deletes *all* `dhcp.@host` entries and *all*
`firewall.@redirect` rules before recreating them from YAML. Anything configured through LuCI and not
represented here is lost on the next apply. `router/apply.sh` is a legacy remnant not used by `make apply`.

## Ingress

Caddy runs in the `proxy` stack on LXC 104 with `network_mode: host`, terminating TLS for
`*.zdraganov.work` and `mdraganova.work` via the Cloudflare DNS-01 challenge (`CLOUDFLARE_API_TOKEN`
serves both Caddy and the `favonia/cloudflare-ddns` sidecar). It reverse-proxies to other LXCs by
`.lan` name, so a hostname in [Caddyfile](stacks/proxy/Caddyfile) must also exist in `router/dns-*.yaml`.
Ports 80/443 reach it only because `router/port-forwards.yaml` DNATs them to `10.66.1.142` — a new
public hostname usually means editing the Caddyfile, the DDNS `DOMAINS` list, and possibly DNS aliases,
then `make deploy STACK=proxy` **and** `make router-apply`.

## Remote deploys

A self-hosted Actions runner on LXC 104 lets the private `mariya_salon` repo redeploy its own stack —
see [docs/actions-runner.md](docs/actions-runner.md), managed via `make runner-install` / `runner-status`
/ `runner-remove`.

The division of labour is deliberate: **GitHub deploys images, the workstation deploys configuration.**
The runner only runs `docker compose pull && up -d && image prune`; it never writes `compose.yaml`
(owned here) or `.env` (needs the age key, which never leaves the workstation). It is triggered by hand
via `make deploy-prod` in the app repo — separate from the image build, and never automatic. Keep that line intact —
a runner that starts writing config would make this repo stop being the source of truth.

Never register a runner against *this* repo: `homelab` is public, and a fork PR can execute arbitrary
code on a self-hosted runner. `mariya_salon` being private is what makes the arrangement safe.

## Validation

```bash
make lint            # terraform validate + python3 yaml.safe_load over every yaml/yml
make status          # qm list + pct list on the host
```

There is no test suite. `make lint` does not catch compose-schema or Caddyfile errors; the proxy stack's
healthcheck runs `caddy validate` only after deploy.
