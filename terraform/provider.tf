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

  ssh {
    agent       = false
    private_key = file(var.ssh_private_key)
    username    = "root"
  }
}
