# Non-secret inputs, committed like ../terraform.tfvars. Secrets come from sops
# via the Makefile (CLOUDFLARE_API_TOKEN, TF_VAR_mcp_secret).

# Zero Trust → Settings → Account details, or any zone's Overview → API.
account_id = "e7f3cf10586bde96996f5c7cf47ff081"
# mdraganova.work → Overview → API → Zone ID.
zone_id = "4ab7b9eb65fadde385b2a6e4af415e5f"

hostname        = "mdraganova.work"
portal_hostname = "mcp.mdraganova.work"

# Google accounts allowed into /admin and the MCP portal.
admin_emails = [
  "mariyanedyalkova2@gmail.com",
  "zhivko.draganov@gmail.com"
]
