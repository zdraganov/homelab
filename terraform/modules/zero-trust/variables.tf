variable "account_id" {
  description = "Cloudflare account that owns the Zero Trust organisation"
  type        = string
}

variable "zone_id" {
  description = "Zone of `hostname`, where the portal's CNAME is created"
  type        = string
}

variable "hostname" {
  description = "Where the site is served, without scheme (e.g. mdraganova.work)"
  type        = string
}

variable "portal_hostname" {
  description = "Hostname for the MCP server portal, on the same zone (e.g. mcp.mdraganova.work)"
  type        = string
}

variable "admin_emails" {
  description = "Google accounts allowed into /admin and the MCP portal"
  type        = list(string)

  validation {
    condition     = length(var.admin_emails) > 0
    error_message = "At least one admin email is required, or nobody can log in."
  }
}

variable "mcp_secret" {
  description = "The app's MCP_SECRET; Cloudflare presents it as a bearer token when calling /api/mcp"
  type        = string
  sensitive   = true
}

variable "mcp_server_id" {
  description = "Identifier of the upstream MCP server in AI Controls. Becomes the tool-name prefix (`<id>_<tool>`), so keep it short and free of underscores."
  type        = string
  default     = "salon"

  validation {
    condition     = can(regex("^[a-z0-9-]{1,32}$", var.mcp_server_id))
    error_message = "Lowercase letters, digits and hyphens only — the portal splits tool names on the first underscore."
  }
}

variable "mcp_portal_id" {
  description = "Identifier of the MCP portal in AI Controls"
  type        = string
  default     = "salon"
}

variable "session_duration" {
  description = "How long an Access login lasts before Google is asked again"
  type        = string
  default     = "24h"
}
