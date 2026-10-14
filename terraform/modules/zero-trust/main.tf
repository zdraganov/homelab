# Cloudflare Zero Trust in front of the salon: who may open /admin, and how AI
# assistants reach the MCP endpoint without the app having to run its own OAuth
# server.
#
# Two things are protected here:
#
#   1. The admin panel — a self-hosted Access application over `/admin` and
#      `/api/admin`, Google login, an email allow-list. This already existed in the
#      dashboard and is imported rather than recreated (see the root README).
#
#   2. The MCP endpoint — registered with Cloudflare's AI Controls as an upstream
#      MCP server and exposed through an MCP server portal on its own hostname.
#      The portal speaks OAuth (with dynamic client registration) to Claude.ai,
#      ChatGPT and Claude Code, logs the human in through the same Google IdP and
#      the same allow-list as /admin, and then calls the app's `/api/mcp` with the
#      static bearer secret the app already checks. Nothing about the app changes.
#
# Neither identity provider is managed here, for two different reasons. Google's
# OAuth client secret is write-only in the API, so importing it would leave
# Terraform unable to tell whether it drifted. One-time PIN has no configuration
# at all to own, and Cloudflare permits exactly one `onetimepin` connection per
# account — creating it returns 409 `access.api.error.conflict` once the account
# has one, which every account that has ever enabled it does. Both are therefore
# looked up by type and referenced by id.

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

data "cloudflare_zero_trust_access_identity_providers" "all" {
  account_id = var.account_id
}

# The one-time PIN connection is a second way in, so a wrong Google account is
# never a locked door.
#
# Signing in to /admin as the wrong Google account used to be unrecoverable.
# Access denies it, the block page offers only "Sign in with: Google", and
# Google — holding a session for the wrong account and never asked to show a
# chooser — hands the same one straight back. On a phone that is a closed loop:
# the admin is installed as a home-screen web app, so there is no address bar to
# reach a logout with and the app's cookie jar is its own, and the only fix left
# was deleting and reinstalling it.
#
# A one-time PIN breaks the loop without touching Google: Access emails a code
# to an address on the allow-list below, so the way back in needs nothing but
# the mailbox. Cloudflare's docs are explicit that OTP and another provider can
# be configured together "to allow users to select their own authentication
# method" — which is also why `auto_redirect_to_identity` has to come off the
# admin application, since it is what skips that choice.
locals {
  google_idps = [for idp in data.cloudflare_zero_trust_access_identity_providers.all.result : idp.id if idp.type == "google"]
  google_idp  = one(local.google_idps)

  onetimepin_idps = [for idp in data.cloudflare_zero_trust_access_identity_providers.all.result : idp.id if idp.type == "onetimepin"]
  onetimepin_idp  = one(local.onetimepin_idps)

  admin_hostname = var.hostname
}

# One allow-list for both applications: the people who may open /admin are
# exactly the people who may drive the salon from an AI assistant.
resource "cloudflare_zero_trust_access_policy" "admins" {
  account_id = var.account_id
  name       = "Salon admins"
  decision   = "allow"

  include = [
    for email in var.admin_emails : {
      email = { email = email }
    }
  ]

  session_duration = var.session_duration
}

# ---------------------------------------------------------------------------
# /admin — the panel Mariya uses
# ---------------------------------------------------------------------------

resource "cloudflare_zero_trust_access_application" "admin" {
  account_id = var.account_id
  name       = "Lashes by Mariya — admin"
  type       = "self_hosted"
  domain     = "${local.admin_hostname}/admin"

  # The admin UI's own API lives under /api/admin and the code assumes the edge
  # protects it — `requireAuth()` in the app is a deliberate no-op. Everything
  # else under /api (bookings, slots, webhooks, mcp) must stay public.
  destinations = [
    { type = "public", uri = "${local.admin_hostname}/admin" },
    { type = "public", uri = "${local.admin_hostname}/api/admin" },
  ]

  # Both methods, and no auto-redirect: together these are what put a second
  # button on the login screen. `auto_redirect_to_identity` sends the visitor
  # straight to the only provider and never shows the picker, so leaving it on
  # would make the one-time PIN unreachable from the very screen that needs it.
  # The cost is one extra tap for Mariya on a normal login.
  allowed_idps              = [local.google_idp, local.onetimepin_idp]
  auto_redirect_to_identity = false
  session_duration          = var.session_duration
  app_launcher_visible      = false

  policies = [{ id = cloudflare_zero_trust_access_policy.admins.id }]
}

# ---------------------------------------------------------------------------
# /api/mcp — the same panel, for AI assistants
# ---------------------------------------------------------------------------

# The app as Cloudflare sees it: an upstream MCP server it calls with a static
# bearer token. This is the `MCP_SECRET` the app checks; Cloudflare's gateway is
# then the only party that needs to know it besides Claude Code users.
resource "cloudflare_zero_trust_access_ai_controls_mcp_server" "salon" {
  account_id  = var.account_id
  id          = var.mcp_server_id
  name        = "Lashes by Mariya — admin"
  description = "Bookings, clients, hours and settings of the salon's admin panel"

  hostname         = "https://${var.hostname}/api/mcp"
  auth_type        = "bearer"
  auth_credentials = var.mcp_secret
}

# Where assistants connect. Tools come through namespaced as
# `<server id>_<tool>`, e.g. `salon_get_overview`.
resource "cloudflare_zero_trust_access_ai_controls_mcp_portal" "salon" {
  account_id  = var.account_id
  id          = var.mcp_portal_id
  name        = "Lashes by Mariya"
  description = "AI assistant access to the salon's admin panel"
  hostname    = var.portal_hostname
  code_mode   = "off"

  servers = [{
    server_id = cloudflare_zero_trust_access_ai_controls_mcp_server.salon.id
    # The upstream uses our static credential, not the end user's own OAuth.
    on_behalf = false
  }]
}

# Each upstream server needs an Access application of its own as well: the
# portal shows a user only the servers whose application admits them, and
# without one the login succeeds and then reports "No allowed servers
# available". The destination says "only via the portal", so nothing here
# exposes the app's /api/mcp path directly. Same IdP and allow-list again.
resource "cloudflare_zero_trust_access_application" "mcp_server" {
  account_id = var.account_id
  name       = "Lashes by Mariya — MCP server"
  type       = "mcp"

  destinations = [{
    type          = "via_mcp_server_portal"
    mcp_server_id = cloudflare_zero_trust_access_ai_controls_mcp_server.salon.id
  }]

  allowed_idps     = [local.google_idp]
  session_duration = var.session_duration

  policies = [{ id = cloudflare_zero_trust_access_policy.admins.id }]
}

# The dashboard creates this record for you; the API and Terraform do not.
resource "cloudflare_dns_record" "portal" {
  zone_id = var.zone_id
  name    = var.portal_hostname
  type    = "CNAME"
  content = "gateway.agents.cloudflare.com"
  proxied = true
  ttl     = 1
  comment = "MCP server portal (Zero Trust AI Controls) — managed by Terraform"
}

# The Access application in front of the portal: this is what runs the OAuth
# conversation with the MCP client and shows the Google login. Same IdP, same
# allow-list as /admin.
#
# The dashboard creates one of these automatically when a portal is made there.
# If the API turns out to do the same, the first apply will refuse to create a
# second application on this hostname — import the existing one instead (see
# the root README) and re-apply; the configuration below then takes it over.
resource "cloudflare_zero_trust_access_application" "portal" {
  account_id = var.account_id
  name       = "Lashes by Mariya — MCP portal"
  type       = "mcp_portal"
  domain     = var.portal_hostname

  allowed_idps              = [local.google_idp]
  auto_redirect_to_identity = true
  session_duration          = var.session_duration

  policies = [{ id = cloudflare_zero_trust_access_policy.admins.id }]

  depends_on = [cloudflare_zero_trust_access_ai_controls_mcp_portal.salon]
}
