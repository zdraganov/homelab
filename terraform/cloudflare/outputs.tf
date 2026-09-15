output "mcp_portal_url" {
  description = "Connect Claude.ai, ChatGPT or Claude Code to this URL; they will be sent through Google login"
  value       = module.zero_trust.mcp_portal_url
}

output "admin_application_id" {
  value = module.zero_trust.admin_application_id
}

output "admin_application_aud" {
  value = module.zero_trust.admin_application_aud
}

output "mcp_portal_application_id" {
  value = module.zero_trust.mcp_portal_application_id
}

output "trypost_application_id" {
  value = module.zero_trust.trypost_application_id
}

output "admins_policy_id" {
  value = module.zero_trust.admins_policy_id
}
