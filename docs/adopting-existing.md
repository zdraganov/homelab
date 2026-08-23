# Adopting Existing Infrastructure

This repo was built on top of a homelab that was already running, and new services are usually adopted
the same way: create them by hand, then bring them under version control. This is the checklist for that.

## Step 1: Import the VM or container into Terraform

There is no separate inventory file — [../terraform/lxc.tf](../terraform/lxc.tf) and
[../terraform/vms.tf](../terraform/vms.tf) are the inventory. Add an entry to the `locals` map
(`lxc_containers` or `vms`) describing what already exists, then import it:

```bash
make tf-import RES='proxmox_virtual_environment_container.lxc["<key>"]' ID=pve/<vmid>
make tf-plan     # iterate until the plan is empty
```

Aim for an empty plan, not a correct-looking one. Anything Terraform still wants to change is something
it would rewrite on the next unrelated `apply`. If a difference cannot be reconciled — usually mount
points, `features`, or the OS template of a hand-built container — add it to `ignore_changes` and record
the real value as a comment in the map, so the next reader knows it is managed on the host.

`prevent_destroy = true` is set on containers deliberately: adoption mistakes should fail, not delete.

## Step 2: Give it a name on the network

Add the host to [../router/dns-hosts.yaml](../router/dns-hosts.yaml) (with its MAC, for a static DHCP
lease) or to `dns-aliases.yaml` (for a DNS-only `.lan` name, which is what services sharing the Dockge
LXC use). Preview and apply:

```bash
python3 router/generate.py      # inspect the generated UCI commands first
make router-apply
```

This replaces *all* DHCP host records and port forwards on the router, so anything configured through
LuCI and not present in these YAML files is lost at this point. Reconcile before applying.

## Step 3: Mirror the Docker stack

Copy the live compose file into `stacks/<name>/compose.yaml` — from Dockge's UI, or straight off the host:

```bash
make exec ID=104 CMD="cat /opt/stacks/<name>/compose.yaml"
```

The directory name is the contract: it must match the remote `/opt/stacks/<name>` directory and the
secrets file basename, or deploys will silently skip the secrets step.

## Step 4: Extract and encrypt secrets

Replace every literal credential in the compose file with a `${VAR}` reference or `env_file: .env`, and
put the values in `secrets/<name>.enc.yaml` as a flat `KEY: value` map — that file is rendered directly to
`/opt/stacks/<name>/.env`, so its top-level keys *are* the stack's environment.

```bash
make encrypt FILE=secrets/<name>.enc.yaml     # first time, on a plaintext file
make edit-secret FILE=secrets/<name>.enc.yaml # thereafter
```

## Step 5: Validate, then deploy over the running service

```bash
make lint            # terraform validate + YAML parse
make check-secrets   # no plaintext credentials in tracked files
make status          # confirm the VM/LXC is where you think it is
make deploy STACK=<name>
```

The first `deploy` overwrites the live compose file and `.env` with the repo's copy. If the transcription
was imperfect, this is where it shows up — check `make exec ID=104 CMD="docker ps"` afterwards.

## Workflow going forward

Change files here, then run the matching apply — `make deploy STACK=<name>`, `make tf-apply`, or
`make router-apply`. Nothing on the server pulls from git, so an unpushed apply and an unapplied commit
are both drift. Commit after deploying, once the change is known to work.
