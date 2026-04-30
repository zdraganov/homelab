variable "proxmox_url" {
  type    = string
  default = "https://pve.lan:8006"
}

variable "proxmox_api_token" {
  type      = string
  sensitive = true
}

variable "ssh_private_key" {
  type    = string
  default = "~/.ssh/homelab_rsa"
}
