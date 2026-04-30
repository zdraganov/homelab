# Homelab GitOps

GitOps repository for managing a Proxmox-based homelab environment.

## Structure

```
.
├── terraform/         # Infrastructure as code (VMs, LXCs)
├── stacks/            # Docker Compose stacks (managed via Dockge)
├── secrets/           # Encrypted secrets (SOPS + age)
├── docs/              # Additional documentation
├── Makefile           # Operational commands
└── .sops.yaml         # SOPS encryption config
```

## Prerequisites

- [age](https://github.com/FiloSottile/age) — `brew install age`
- [sops](https://github.com/getsops/sops) — `brew install sops`
- [Terraform](https://www.terraform.io/) — `brew install terraform`

## Quick Start

```bash
# 1. Generate SSH key for Proxmox access
ssh-keygen -t rsa -f ~/.ssh/homelab_rsa -C "homelab"

# 2. Copy public key to Proxmox host (will prompt for password once)
ssh-copy-id -i ~/.ssh/homelab_rsa.pub root@pve.lan

# 3. Initialize secret encryption
make secrets-init

# 4. Update .sops.yaml with the public key printed above

# 5. Initialize Terraform
make tf-init
```

## Infrastructure Management

```bash
make tf-plan             # Preview changes
make tf-apply            # Apply changes
make status              # Show all VMs/LXCs
make shell ID=104        # Enter a LXC shell
make exec ID=104 CMD="…" # Run command in LXC
```

## Stack Management

```bash
make deploy STACK=proxy      # Sync + secrets + restart
make sync STACK=proxy        # Sync compose only
make sync-secrets STACK=proxy # Push decrypted .env
```

## Secret Management

```bash
make edit-secret FILE=secrets/proxy.enc.yaml   # Edit in $EDITOR
make decrypt-file FILE=secrets/proxy.enc.yaml  # Decrypt to .dec.yaml
make encrypt-file FILE=secrets/proxy.dec.yaml  # Re-encrypt
```

## All Commands

```bash
make help
```
