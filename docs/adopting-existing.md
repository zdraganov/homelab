# Adopting Existing Infrastructure

## Step 1: Document your Proxmox inventory

Edit `infrastructure/inventory.yaml` with your actual VMs and LXC containers. Include IDs, IPs, resource allocations, and purpose.

## Step 2: Mirror your Dockge stacks

For each stack running in Dockge, create a matching directory:

```
stacks/<stack-name>/compose.yaml
```

Copy the compose content from Dockge's UI or from the host at Dockge's stacks directory (typically `/opt/stacks/<name>/compose.yaml`).

## Step 3: Extract and encrypt secrets

For any stack that uses secrets (DB passwords, API keys, etc.):

1. Create a secrets file: `secrets/<stack-name>.enc.yaml`
2. Add the secret values
3. Encrypt: `make encrypt FILE=secrets/<stack-name>.enc.yaml`
4. Reference in your compose files using `env_file` or variable substitution

## Step 4: Validate

```bash
make lint           # Check YAML syntax
make check-secrets  # Ensure no plaintext secrets
make stack-ps       # Verify stack status
```

## Workflow going forward

1. Make changes in this repo
2. Encrypt any new secrets
3. Commit and push
4. Deploy to server (manually or via CI)
