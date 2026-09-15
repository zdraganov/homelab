# TryPost (social media scheduler)

[TryPost](https://github.com/trypostit/trypost) schedules and publishes posts to Instagram, Facebook,
Threads, TikTok, YouTube and the rest from one calendar. It runs as the `trypost` Docker stack on the
**Dockge LXC (104, `10.66.1.142`)** at `https://post.mdraganova.work`, behind Caddy like the salon app.

Request path:

```
Internet :443 → Cloudflare Access (Google login, salon allow-list; /storage bypassed)
              → OpenWrt DNAT (router/port-forwards.yaml) → 10.66.1.142
              → Caddy (stacks/proxy/Caddyfile)  post.mdraganova.work → dockge.lan:8010
                  → nginx inside the trypost container
                      /app/, /apps/  → Reverb WebSocket server (same container, :8080)
                      everything     → php-fpm
```

## Access: who can open it

The whole hostname sits behind Cloudflare Access with the same Google login and `admin_emails`
allow-list as the salon's `/admin`, managed in [../terraform/modules/zero-trust/main.tf](../terraform/modules/zero-trust/main.tf)
(`make cf-plan` / `make cf-apply`). Two things shape it:

- **`/storage` is bypassed.** Instagram, Threads, TikTok and Pinterest do not receive the media file
  from TryPost; they receive `https://post.mdraganova.work/storage/...` and fetch it themselves, so a
  second Access application on that path admits everyone. Access applies the most specific path.
- **OAuth callbacks need no exception.** Meta and TikTok send the browser back to
  `/accounts/<platform>/callback`, and the browser carries the Access cookie.

Two logins are deliberate: TryPost cannot trust the identity Access verified (no header or JWT
support), so it keeps its own password login. Its "Continue with Google" button (`GOOGLE_AUTH_ENABLED`)
would reduce that to one click, but its callback also registers any Google user it has not seen,
so leave it off unless the extra Google OAuth client setup becomes worth it.

- **The MCP OAuth machine paths are bypassed too.** TryPost is its own OAuth 2.1 server for MCP
  (dynamic client registration + PKCE via Passport; API keys are refused there), which is what
  Claude.ai and Claude Code speak natively, so no Cloudflare MCP portal is needed. Their servers call
  `/.well-known/oauth-*`, `/oauth/register`, `/oauth/token` and `/mcp/trypost` without a browser, so
  those are in the same bypass application. `/oauth/authorize`, the consent page, stays behind Access:
  every new authorization still goes through Google, then TryPost's login, then Allow.

What Access does block: TryPost's REST API for bearer-token clients (API keys).

TikTok wants domain ownership proven for `mdraganova.work` (the terms and privacy pages) and for
`post.mdraganova.work` (it only pulls videos from a verified domain), and the production app and its
sandbox each issue their own token. All of them are `tiktok-developers-site-verification=…` TXT
records managed in the Zero Trust module from the `tiktok_verifications` map in
`terraform/cloudflare/variables.tf` (hostname → app label → token); a new token from the TikTok portal
means editing that map and a targeted `make cf-apply` of
`module.zero_trust.cloudflare_dns_record.tiktok_verification`.

### Connecting an AI assistant

- Claude.ai: Settings → Connectors → Add custom connector, URL `https://post.mdraganova.work/mcp/trypost`.
- Claude Code: `claude mcp add --transport http trypost https://post.mdraganova.work/mcp/trypost`.

The first tool call opens the browser for the Access Google login, the TryPost login and the Allow
button. The token is bound to the TryPost workspace of the account that clicked Allow. Symptom of the
bypass missing: "Couldn't register with … sign-in service" from Claude.ai, because `/oauth/register`
answered with an Access redirect instead of JSON.

## Stack services

Defined in [../stacks/trypost/compose.yaml](../stacks/trypost/compose.yaml):

| Service | Purpose |
| --- | --- |
| `app` | `ghcr.io/trypostit/trypost:<version>`, pinned. One container runs nginx, php-fpm, Horizon (queue), Reverb (WebSockets) and the scheduler. Published on `8010`. Migrations run on every start. |
| `pgsql` | `postgres:16-alpine`, data in the `pgdata` volume |
| `redis` | `redis:7-alpine` with AOF, queue + cache backend, data in `redisdata` |
| `backup` | crond running `pg_dump` daily at 03:00 into `/mnt/trypost/backups` on the LXC, pruning dumps older than 7 days |

Uploaded media lives in the `storage` Docker volume (`/var/www/html/storage/app`), not on a Proxmox
mount. The nightly dump does not include it.

## First run

1. Create the secrets file. Everything the app needs at boot is generated; the rest is left empty:

   ```bash
   cd stacks/trypost && make init-secrets
   ```

2. Put in the Resend API key (`MAIL_PASSWORD`) and check `MAIL_FROM_ADDRESS`, so password resets and
   invites can be sent. Social credentials can wait until each network is connected (below).

   ```bash
   make edit-secret FILE=secrets/trypost.enc.yaml    # from the repo root
   ```

3. Ingress and DNS. The hostname is already in [../stacks/proxy/Caddyfile](../stacks/proxy/Caddyfile)
   and in the DDNS `DOMAINS` list; the proxy stack only needs redeploying so DDNS creates the record
   and Caddy issues the certificate. Then put Access in front of it:

   ```bash
   make deploy STACK=proxy
   make cf-plan        # expect two Access applications and one bypass policy to be created
   make cf-apply TARGETS="module.zero_trust.cloudflare_zero_trust_access_application.trypost \
                          module.zero_trust.cloudflare_zero_trust_access_policy.trypost_media \
                          module.zero_trust.cloudflare_zero_trust_access_application.trypost_media"
   ```

   The targeted apply is deliberate: an untargeted plan also wants to flip `on_behalf` on the salon's
   MCP portal, a perpetual-diff bug in the Cloudflare provider
   ([#7294](https://github.com/cloudflare/terraform-provider-cloudflare/issues/7294)), and applying
   that would break the salon's MCP connection.

4. Deploy the stack, then seed the plan rows, the Passport client and the admin user:

   ```bash
   cd stacks/trypost
   make deploy
   make logs        # wait for "[entrypoint] ready — handing off to supervisord"
   make init
   ```

5. Open <https://post.mdraganova.work>: Google login first (Access), then TryPost's own login as
   `admin@trypost.it` / `password`. Change both in the profile immediately. Registration is closed
   (`SELF_HOSTED=true`); further users are invited from inside the app and also need to be in
   `admin_emails`.

## Connecting social accounts

Each network needs an app in its developer portal, with this redirect URI:

```
https://post.mdraganova.work/accounts/<platform>/callback
```

- **Meta (Facebook + Instagram)** — one app at <https://developers.facebook.com> with the
  *Facebook Login for Business* product, and only `FACEBOOK_CLIENT_ID/SECRET` filled in. Instagram
  connects through the same app via the linked Facebook Page (`/accounts/instagram-facebook/callback`),
  so register both `/accounts/facebook/callback` and that URI. Mariya's Facebook account needs a role on
  the app while it stays in Development mode. The standalone Instagram login (`INSTAGRAM_*`) and Threads
  (`THREADS_*`) are deliberately not set up; their keys stay empty in the secrets file.
- **Callback URLs are also env vars.** Socialite reads `<PLATFORM>_CLIENT_REDIRECT` for each platform
  and upstream only defaults them from `APP_URL` in a `.env` file, which a container environment does
  not get. They are not secret, so they live in the compose file (`FACEBOOK_CLIENT_REDIRECT` today).
  The symptom of a missing one is "No redirect present in URI" when clicking Connect. Adding TikTok
  later means adding `TIKTOK_CLIENT_REDIRECT` the same way.
- **TikTok** — <https://developers.tiktok.com>, enable Login Kit and the Content Posting API. Keys
  `TIKTOK_CLIENT_ID/SECRET`.
- **YouTube** — not used. If it ever is, it needs a Google Cloud OAuth client with the YouTube Data
  API enabled and `GOOGLE_CLIENT_ID/SECRET` added to the secrets file.
- **Bluesky, Mastodon** need no credentials; Telegram and Discord use bot tokens.

Per-platform walkthroughs, including which permissions to request during Meta app review, are at
<https://docs.trypost.it/platforms/>. After adding keys:

```bash
make edit-secret FILE=secrets/trypost.enc.yaml
cd stacks/trypost && make deploy
```

## Day-to-day commands

Run from [../stacks/trypost/](../stacks/trypost/):

```bash
make deploy                       # sync compose + .env, docker compose up -d
make redeploy                     # as above plus docker compose pull (after a tag bump)
make logs                         # tail the app container
make artisan CMD="horizon:status" # any artisan command
make backup-now                   # one-off timestamped pg_dump
```

## Upgrading

Releases are at <https://github.com/trypostit/trypost/releases>. Some migrations rewrite data, so:

```bash
cd stacks/trypost
make backup-now
# bump the image tag in compose.yaml
make redeploy                     # the entrypoint runs migrate --force on start
```

## Known limitation: live updates in the browser

The published image bakes the WebSocket client to `ws://localhost:8080` (Vite inlines
`VITE_REVERB_*` at build time and the upstream release workflow only sets the app key). Everything
that matters — scheduling, publishing, token refresh — is done server-side by Horizon and the
scheduler and is unaffected. What is lost is the real-time push: post status changes appear on
reload rather than instantly, and the browser console shows a failed WebSocket connection.

Fixing it means building the image with `--build-arg VITE_REVERB_HOST=post.mdraganova.work
VITE_REVERB_PORT=443 VITE_REVERB_SCHEME=https VITE_REVERB_APP_KEY=trypost-reverb-key` (target
`production`, `docker/Dockerfile`). The build needs PHP, Node and a Vite SSR pass, which is too heavy
to do on the 4 GB LXC next to the salon; the reasonable home for it is a GitHub Actions workflow that
publishes `ghcr.io/zdraganov/trypost` and a tag bump here, the same split as the salon image.

## Notes

- `post.mdraganova.work` is proxied through Cloudflare like the apex, which is also what lets Access
  sit in front of it. The free plan caps request bodies at 100 MB, which bounds a single video
  upload. Caddy itself has no limit; the container's nginx allows 1 GB.
- Laravel trusts all proxies upstream (`trustProxies(at: '*')`), so `https://` URLs and the OAuth
  callbacks are generated correctly behind Caddy and Cloudflare.
- `REVERB_APP_KEY` is intentionally not a secret: it is the value compiled into the public image.
- The Passport keys in the secrets file are what make API and MCP tokens survive a container
  recreate; regenerating them invalidates every issued token.
