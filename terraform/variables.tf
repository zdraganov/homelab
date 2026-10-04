variable "proxmox_url" {
  type    = string
  default = "https://pve.lan:8006"
}

variable "proxmox_api_token" {
  type      = string
  sensitive = true
}

# Unused: provider.tf authenticates through the SSH agent. Kept declared only because
# terraform.tfvars still sets it — delete that line and this block together.
variable "ssh_private_key" {
  type    = string
  default = ""
}
