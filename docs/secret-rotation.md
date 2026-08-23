# Secret Rotation Log

Log of credential rotations, newest first. Record the date, the reason, and anything the next
rotation would otherwise have to rediscover.

## Cloudflare API Token — rotated 2026-08-23

- **Secret**: `CLOUDFLARE_API_TOKEN` in `secrets/proxy.enc.yaml`
- **Reason**: the previous token was exposed in plaintext during initial infrastructure discovery
- **Status**: rotated and deployed

### What this token has to cover

It is shared by **both** services in the `proxy` stack, and between them they span **two zones**:

| Consumer | Uses it for | Hostnames |
| --- | --- | --- |
| Caddy (`acme_dns cloudflare`) | ACME DNS-01 challenge | `mdraganova.work`, `www.mdraganova.work`, `plex.zdraganov.work`, `photos.zdraganov.work` |
| `favonia/cloudflare-ddns` | Updating A records | the `DOMAINS` list in `stacks/proxy/compose.yaml` |

So the token needs `Zone:DNS:Edit` + `Zone:Zone:Read` on **`zdraganov.work` *and* `mdraganova.work`**.

A token scoped to only one zone appears to work: existing certificates stay valid, so the failure does
not surface until a renewal weeks later. Check the scope at rotation time, not afterwards.

### Procedure

```bash
# 1. Roll the token at https://dash.cloudflare.com/profile/api-tokens
# 2. Update the encrypted secret
make edit-secret FILE=secrets/proxy.enc.yaml
# 3. Deploy
make deploy STACK=proxy
# 4. Verify — ddns exercises the token within a minute; Caddy not until a renewal
make exec ID=104 CMD="docker logs --tail 50 cloudflare-ddns"
make exec ID=104 CMD="docker logs --tail 50 caddy"
```

The `cloudflare-ddns` log is the fast signal: a successful record update means the credential is good.

### Dashboard notices that do *not* apply

The API tokens page also shows deprecation warnings for the **Global API Key** and the **Origin CA Key**.
Neither is used anywhere in this repo — there is no `CLOUDFLARE_EMAIL` / `X-Auth-Email` style credential
in any stack. Ignore both notices when rotating.

## Open items

- `secrets/cloudflared.enc.yaml` holds a `CLOUDFLARED_TUNNEL_TOKEN` with **no corresponding stack** in
  `stacks/`. Likely superseded by the Caddy + DDNS ingress. Revoke the tunnel token and delete the file
  if tunnels are genuinely abandoned.
