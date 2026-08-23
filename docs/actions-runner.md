# Self-Hosted Actions Runner

Lets the **`mariya_salon`** repo deploy to the homelab from a GitHub Actions workflow, without opening
any inbound path into the network.

## Why a runner rather than a webhook

Nothing reaches the homelab from the internet except ports 80, 443 and 32400, and none of them is SSH.
A push-based deploy would need new ingress — a tunnel, a mesh VPN, or a public webhook endpoint.
A self-hosted runner inverts that: it **long-polls GitHub outbound**, so there is no new listener, no
port forward, and no SSH key or age key stored in GitHub secrets.

It also runs a real `docker compose up`, which matters here: `app` declares
`depends_on: migrate: condition: service_completed_successfully`. Container-level updaters such as
Watchtower restart individual containers and would bypass that ordering, starting a new `app` against
an unmigrated database. Anything that deploys this stack must go through compose.

## What the runner is allowed to do

The deploy job **only pulls images and restarts the stack**. It deliberately does not:

- check out the application source (nothing on the LXC needs it)
- write `compose.yaml` — that is owned by this repo and pushed by `make sync`
- write `.env` — that requires the age key, which never leaves the workstation

So the split stays clean: **GitHub deploys new images, the workstation deploys new configuration.**
A config change is still `make deploy STACK=mariya-salon` from here.

## Install

```bash
make runner-install      # registers against RUNNER_REPO (default zdraganov/mariya_salon)
make runner-status       # service state on the LXC + registration state on GitHub
make runner-remove       # stop, uninstall, deregister, delete the directory
```

`runner-install` fetches a short-lived registration token via the `gh` CLI, pushes
[../scripts/install-runner.sh](../scripts/install-runner.sh) into LXC 104 and runs it. The token is
passed as a file rather than an argument so it never appears in the Proxmox host's process table.
The runner tarball is checksum-verified against `RUNNER_SHA256` in the root `Makefile`.

Re-running it is safe — `--replace` takes over the existing registration instead of accumulating dead
runner entries.

### Upgrading the runner

GitHub deprecates old runner versions. Bump both variables together in the root `Makefile` and re-run:

```bash
gh api repos/actions/runner/releases/latest --jq '.tag_name'
gh api repos/actions/runner/releases/latest \
  --jq '.assets[] | select(.name|test("linux-x64-[0-9]")) | .digest'
make runner-install
```

## Security

The runner is registered to **`mariya_salon`, which is private**. That is load-bearing. A self-hosted
runner on a *public* repo is a known foot-gun: a pull request from a fork can execute arbitrary code on
it. For the same reason, **never register a runner against this repo — `homelab` is public.**

The deploy job is additionally gated to `refs/heads/main` and has no `pull_request` trigger.

Two limitations to be honest about:

- The runner user is in the `docker` group, which is **root-equivalent** on the container. Running as
  `github-runner` rather than `root` limits accidents, not a determined attacker.
- LXC 104 is a **privileged** container (`unprivileged = false` in `terraform/lxc.tf`). The hop from
  container root to host root is meaningfully shorter than it would be in an unprivileged container.

Combined: anyone who can run code in that repo's workflows can, in principle, reach the Proxmox host.
That is an acceptable trade for a single-operator private repo. It would not be for a repo with outside
contributors.

## Disk

Every `docker compose pull` on a mutable tag orphans the previous image. Before this was automated the
LXC had reached **81% of its 20 GB root with ~10 GB of dangling layers** — enough that the next pull
would have failed and taken the site down. The deploy job therefore ends with `docker image prune -f`;
treat that step as part of the deploy, not as optional tidying.

Note that Docker 29 stores layers under `/var/lib/containerd`, not `/var/lib/docker`, so
`du -sh /var/lib/docker` badly understates real usage. Use `docker system df`.

```bash
make exec ID=104 CMD="docker system df"
make exec ID=104 CMD="df -h /"
```

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| Job queued forever | Runner offline — `make runner-status`, then `systemctl status 'actions.runner.*'` on the LXC |
| `denied` / `unauthorized` on pull | ghcr credentials expired — `make setup-docker-auth` |
| `no space left on device` | Prune step never ran — `make exec ID=104 CMD="docker image prune -f"` |
| Runner fails to start after install | Missing .NET deps — re-run `./bin/installdependencies.sh` in `/opt/actions-runner` |
