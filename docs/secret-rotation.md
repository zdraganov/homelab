# Secret Rotation Log

## Cloudflare API Token
- **Status**: NEEDS ROTATION
- **Reason**: Token was exposed in plaintext during initial infrastructure discovery
- **Steps**:
  1. Go to https://dash.cloudflare.com/profile/api-tokens
  2. Roll (or delete + recreate) the token used for DDNS
  3. Update locally: `make edit-secret FILE=secrets/proxy.enc.yaml`
  4. Deploy: `make deploy STACK=proxy`
