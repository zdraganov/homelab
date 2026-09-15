output "admin_application_id" {
  description = "Access application protecting /admin and /api/admin"
  value       = cloudflare_zero_trust_access_application.admin.id
}

output "admin_application_aud" {
  description = "Audience tag of the admin application, should the app ever verify Cf-Access-Jwt-Assertion itself"
  value       = cloudflare_zero_trust_access_application.admin.aud
}

output "admins_policy_id" {
  description = "The reusable allow-list policy shared by both applications"
  value       = cloudflare_zero_trust_access_policy.admins.id
}

output "google_identity_provider_id" {
  value = local.google_idp
}

output "mcp_portal_url" {
  description = "What to paste into Claude.ai, ChatGPT or `claude mcp add --transport http`"
  value       = "https://${var.portal_hostname}/mcp"
}

output "mcp_portal_application_id" {
  value = cloudflare_zero_trust_access_application.portal.id
}

output "trypost_application_id" {
  description = "Access application in front of the whole TryPost hostname"
  value       = cloudflare_zero_trust_access_application.trypost.id
}

output "trypost_media_application_id" {
  description = "The bypass application for /storage (media the platforms fetch) and the MCP OAuth machine paths"
  value       = cloudflare_zero_trust_access_application.trypost_media.id
}

output "mcp_server_application_id" {
  description = "Access application admitting users to the salon server through the portal"
  value       = cloudflare_zero_trust_access_application.mcp_server.id
}
