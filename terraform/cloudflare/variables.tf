variable "account_id" {
  description = "Cloudflare account id (dashboard → any zone → Overview → API, or Zero Trust → Settings)"
  type        = string
}

variable "zone_id" {
  description = "Zone id of the site's domain"
  type        = string
}

variable "hostname" {
  description = "Where the site is served"
  type        = string
  default     = "mdraganova.work"
}

variable "portal_hostname" {
  description = "Hostname of the MCP server portal, on the same zone"
  type        = string
  default     = "mcp.mdraganova.work"
}

variable "admin_emails" {
  description = "Google accounts allowed into /admin and the MCP portal"
  type        = list(string)
}

variable "mcp_secret" {
  description = "Same value as MCP_SECRET in the app's .env (secrets/mariya-salon.enc.yaml in the homelab repo)"
  type        = string
  sensitive   = true
}
