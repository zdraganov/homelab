terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.78"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_url
  api_token = var.proxmox_api_token
  insecure  = true

  # The Proxmox key's private half is in the Bitwarden SSH agent, not on disk, so there is
  # no file for private_key to read — use the agent via SSH_AUTH_SOCK instead.
  ssh {
    agent    = true
    username = "root"
  }
}
