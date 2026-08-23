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

The deploy lives in its own workflow — `deploy.yml` in the app repo, `workflow_dispatch` only, triggered
with `make deploy-prod` from there. It is deliberately separate from `build.yml`: publishing an image and
putting it into production are different decisions.

The deploy job **only pulls images and restarts the stack**. It deliberately does not:

- check out the application source (nothing on the LXC needs it)
- write `compose.yaml` — that is owned by this repo and pushed by `make sync`
- write `.env` — that requires the age key, which never leaves the workstation

So the split stays clean: **GitHub deploys new images, the workstation deploys new configuration.**
A config change is still `make deploy STACK=mariya-salon` from here.

Note the deploy is **ref-independent**: it pulls whatever ghcr serves for `:latest` and never checks out
the app repo, so dispatching it from a branch does not deploy that branch.

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

**Run `make setup-docker-auth` after the first install.** Docker keeps credentials per-user in
`$HOME/.docker/config.json`, so logging in as root leaves the runner user unauthenticated. The symptom is
confusing: deploys fail with `error from registry: unauthorized` while the identical pull works fine when
you try it by hand over SSH, because that lands you as root. `setup-docker-auth` now logs in as both, and
skips the runner user with a note if it does not exist yet.

### Adding a second repo

GitHub scopes self-hosted runners at **repository, organization or enterprise** level — there is no
account level. `zdraganov` is a personal user account, so two personal repos cannot share one runner;
each needs its own registration.

```bash
make runner-install RUNNER_REPO=zdraganov/some-other-app
```

Installs are namespaced by repo (`/opt/actions-runner/<repo>`, one systemd service each), so this adds a
runner rather than replacing the existing one. Getting that wrong is quiet and unpleasant: the second
install would take over the first's directory and service, and you would find out when the salon's
deploys started queueing forever.

Each runner costs roughly 200 MB of disk and a ~150 MB idle process. Two or three is fine on this LXC;
past that, an organization-scoped runner is the better shape.

### If you outgrow per-repo runners

Sharing one runner across repos requires a **GitHub organization** (free). Three things have to be true
before that is safe or even correct:

1. **Only private repos in the org.** A private repo cannot take fork PRs from strangers, which is the
   attack that makes self-hosted runners dangerous. GitHub's own guidance is to use self-hosted runners
   only with private repositories. Runner *groups* would let you scope access explicitly, but the docs
   disagree about whether the free plan can create them — do not depend on that toggle. `homelab` is
   public today and would have to become private first.
2. **Registration moves to the org endpoint.** `/orgs/{org}/actions/runners/registration-token` rather
   than the repo one, registered against the org URL. `make runner-install` would need updating.
3. **The ghcr image path changes.** `build.yml` derives its image name from `${{ github.repository }}`,
   so transferring a repo moves publishes from `ghcr.io/zdraganov/<app>` to `ghcr.io/<org>/<app>`. Any
   `compose.yaml` pinning the old path keeps pulling a now-frozen image — deploys report success while
   running stale code. Update the compose file in the same change and re-verify `make setup-docker-auth`.

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

`deploy.yml` is `workflow_dispatch` only — there is no `push` or `pull_request` trigger, so a deploy
never happens without someone asking for one.

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
| Job queued forever | Runner offline — `make runner-status`, then `systemctl status 'actions.runner.*'` on the LXC. `make deploy-prod` pre-checks this and refuses to dispatch |
| `denied` / `unauthorized` on pull | ghcr credentials missing for the *runner user* — `make setup-docker-auth`. Docker stores credentials per-user, so a login as root does nothing for the runner |
| `no space left on device` | Prune step never ran — `make exec ID=104 CMD="docker image prune -f"` |
| Runner fails to start after install | Missing .NET deps — re-run `./bin/installdependencies.sh` in `/opt/actions-runner` |
