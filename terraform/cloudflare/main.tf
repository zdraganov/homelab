# Cloudflare side of mdraganova.work: Zero Trust in front of /admin and the MCP
# server portal that lets AI assistants use the salon's admin panel.
#
# A separate root from ../ (Proxmox) because it needs a different credential and
# its own state; the resources themselves live in ../modules/zero-trust.
#
# Credentials: `CLOUDFLARE_API_TOKEN` in the environment, which `make cf-*`
# decrypts from secrets/terraform-cloudflare.enc.yaml. `mcp_secret` is passed as
# TF_VAR_mcp_secret from secrets/mariya-salon.enc.yaml, so the app and Cloudflare
# always agree on it.
#
# State is local and gitignored like the Proxmox root. It contains `mcp_secret`.

terraform {
  required_version = ">= 1.5"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

provider "cloudflare" {}

module "zero_trust" {
  source = "../modules/zero-trust"

  account_id      = var.account_id
  zone_id         = var.zone_id
  hostname        = var.hostname
  portal_hostname = var.portal_hostname
  admin_emails    = var.admin_emails
  mcp_secret      = var.mcp_secret
}
