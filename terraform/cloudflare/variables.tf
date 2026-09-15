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

variable "trypost_hostname" {
  description = "Hostname of TryPost (stacks/trypost), on the same zone"
  type        = string
  default     = "post.mdraganova.work"
}

variable "tiktok_verifications" {
  description = "TikTok domain-verification tokens per hostname and app (public by nature, they end up in DNS)"
  type        = map(map(string))
  default = {
    # terms + privacy pages
    "mdraganova.work" = {
      production = "tCntljB7kxAA2uc79ySpWHdffxNyNE81"
      sandbox    = "H0EqM4T57oIzE79SKgVGhcp2HvcBkaJT"
    }
    # media URL prefix /storage/
    "post.mdraganova.work" = {
      production = "Tk6vXdh7Lg336iLz9tDaZ5MWquWZ0lKG"
      sandbox    = "t7y1VdztIa8tYprjywr8nhDAhqJs8yKT"
    }
  }
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
