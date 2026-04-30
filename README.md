# Homelab GitOps

GitOps repository for managing a Proxmox-based homelab environment.

## Structure

```
.
├── ansible/           # Ansible playbooks and inventory
├── infrastructure/    # Proxmox inventory (VMs, LXCs, services)
├── stacks/            # Docker Compose stacks (managed via Dockge)
├── secrets/           # Encrypted secrets (SOPS + age)
├── docs/              # Additional documentation
├── Makefile           # Operational commands
└── .sops.yaml         # SOPS encryption config
```

## Prerequisites

- [age](https://github.com/FiloSottile/age) — `brew install age`
- [sops](https://github.com/getsops/sops) — `brew install sops`
- [Ansible](https://docs.ansible.com/) — `pip install ansible-core`
- Docker (for local stack testing)

```bash
# Install Ansible collections
ansible-galaxy collection install -r ansible/requirements.yaml
```

## Quick Start

```bash
# 1. Generate SSH key for Proxmox access
ssh-keygen -t rsa -f ~/.ssh/homelab_rsa -C "homelab"

# 2. Copy public key to Proxmox host (will prompt for password once)
ssh-copy-id -i ~/.ssh/homelab_rsa.pub root@pve.lan

# 3. Initialize secret encryption
make secrets-init

# 4. Update .sops.yaml with the public key printed above

# 5. Fill in infrastructure/inventory.yaml with your actual VMs/LXCs

# 6. Add your existing stacks under stacks/<name>/compose.yaml
```

## Secret Management

Secrets are encrypted with SOPS using age keys. The private key (`secrets/age.key`) is gitignored and must be kept safe.

```bash
# Create and encrypt a secret
cp secrets/example.yaml secrets/myapp.enc.yaml
# Edit values, then:
make encrypt FILE=secrets/myapp.enc.yaml

# Edit an encrypted secret
make edit-secret FILE=secrets/myapp.enc.yaml

# Decrypt to stdout
make decrypt FILE=secrets/myapp.enc.yaml
```

## Infrastructure Management

```bash
make status                  # Show all VMs/LXCs
make start ID=101            # Start a VM or LXC
make stop ID=101             # Stop a VM or LXC
make restart ID=101          # Restart a VM or LXC
make shell ID=104            # Enter a LXC shell
make exec ID=104 CMD="..."   # Run command in LXC
make create-lxc ID=107 HOSTNAME=myapp  # Create new LXC
```

## Stack Management

```bash
make deploy STACK=proxy      # Sync + secrets + restart
make sync STACK=proxy        # Sync compose only
make sync-secrets STACK=proxy # Push decrypted .env
```

## All Commands

```bash
make help
```
