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
#   3. TryPost — the social media scheduler on its own hostname. The whole host
#      sits behind the same login and allow-list, except `/storage`: Instagram,
#      Threads, TikTok and Pinterest never receive the media file, they receive a
#      URL and fetch it themselves, so that path is bypassed (docs/trypost.md).
#
# The Google identity provider itself stays managed in the dashboard: its OAuth
# client secret is write-only in the API, so importing it would leave Terraform
# unable to tell whether it drifted. It is looked up by type instead.

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

locals {
  google_idps = [for idp in data.cloudflare_zero_trust_access_identity_providers.all.result : idp.id if idp.type == "google"]
  google_idp  = one(local.google_idps)

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

  allowed_idps              = [local.google_idp]
  auto_redirect_to_identity = true
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

# ---------------------------------------------------------------------------
# TryPost — the scheduler, and the media path the platforms pull from
# ---------------------------------------------------------------------------

# The mirror image of /admin: here the whole hostname is protected and one
# path is opened. OAuth callbacks from Meta and TikTok land on
# /accounts/<platform>/callback as browser redirects, so they carry the Access
# cookie and need no exception. Only API/MCP bearer-token clients would be
# stopped by this, and none exist yet.
resource "cloudflare_zero_trust_access_application" "trypost" {
  account_id = var.account_id
  name       = "TryPost"
  type       = "self_hosted"
  domain     = var.trypost_hostname

  allowed_idps              = [local.google_idp]
  auto_redirect_to_identity = true
  session_duration          = var.session_duration
  app_launcher_visible      = false

  policies = [{ id = cloudflare_zero_trust_access_policy.admins.id }]
}

# Bypass is a decision, so it still needs a policy; "everyone" is the only
# sensible include for paths that machines, not people, must reach.
resource "cloudflare_zero_trust_access_policy" "trypost_media" {
  account_id = var.account_id
  name       = "TryPost machine paths — public"
  decision   = "bypass"

  include = [{ everyone = {} }]
}

# Access applies the application with the most specific path, so these win over
# the host-wide one above. Two kinds of path are opened:
#
#   /storage — media. Files have Laravel's hashed names and are the images
#     about to be posted publicly; Meta's and TikTok's fetchers pull them.
#
#   The MCP OAuth machinery — TryPost is its own OAuth 2.1 server (dynamic
#     client registration + PKCE, via Passport) and Claude.ai / Claude Code talk
#     to it server-to-server: discovery under /.well-known, /oauth/register,
#     /oauth/token, and the tool endpoint /mcp/trypost, which only accepts the
#     tokens that flow issues. The consent page /oauth/authorize is deliberately
#     NOT here: that is the browser step, and Access plus TryPost's own login
#     gate every new authorization there.
resource "cloudflare_zero_trust_access_application" "trypost_media" {
  account_id = var.account_id
  name       = "TryPost — machine paths (bypass)"
  type       = "self_hosted"
  domain     = "${var.trypost_hostname}/storage"

  destinations = [
    { type = "public", uri = "${var.trypost_hostname}/storage" },
    { type = "public", uri = "${var.trypost_hostname}/.well-known/oauth-protected-resource" },
    { type = "public", uri = "${var.trypost_hostname}/.well-known/oauth-authorization-server" },
    { type = "public", uri = "${var.trypost_hostname}/oauth/register" },
    { type = "public", uri = "${var.trypost_hostname}/oauth/token" },
    { type = "public", uri = "${var.trypost_hostname}/mcp/trypost" },
  ]

  app_launcher_visible = false

  policies = [{ id = cloudflare_zero_trust_access_policy.trypost_media.id }]
}

# TikTok for Developers asks for domain ownership twice: the apex, where the
# terms and privacy pages the app review points at live, and the TryPost host,
# because TikTok only pulls videos from a verified domain and TryPost hands it
# URLs under https://<trypost_hostname>/storage/. Each is a TXT record next to
# an A record managed elsewhere (the apex and post host by the DDNS sidecar in
# the proxy stack); TXT and A coexist, only CNAME would not. The production app
# and its sandbox each issue their own token, so a hostname carries one record
# per token.
locals {
  tiktok_verification_records = merge([
    for host, tokens in var.tiktok_verifications : {
      for label, token in tokens : "${host}/${label}" => { name = host, label = label, token = token }
    }
  ]...)
}

resource "cloudflare_dns_record" "tiktok_verification" {
  for_each = local.tiktok_verification_records

  zone_id = var.zone_id
  name    = each.value.name
  type    = "TXT"
  content = "tiktok-developers-site-verification=${each.value.token}"
  ttl     = 1
  comment = "TikTok for Developers domain verification, ${each.value.label} app (TryPost) — managed by Terraform"
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
