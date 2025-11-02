# Cloudflare DNS Management with OpenTofu

This directory contains OpenTofu (Terraform) configuration for managing Cloudflare DNS records for `dimensiondoor.xyz`.

## Prerequisites

- OpenTofu (available in the nix dev shell)
- Cloudflare API token with DNS edit permissions
- SOPS age key for encrypting secrets

## Initial Setup

### 1. Get Cloudflare Credentials

1. Log into your Cloudflare dashboard
2. Go to **Profile** → **API Tokens**
3. Create a new API token with these permissions:
   - **Zone - DNS - Edit**
   - **Zone - Zone - Read**
   - For zone: `dimensiondoor.xyz`
4. Copy the API token (you'll only see it once!)
5. Get your Zone ID:
   - Go to your domain overview in Cloudflare
   - Scroll down to find **Zone ID** on the right sidebar
   - Copy the Zone ID

### 2. Add Secrets to SOPS

Edit the encrypted secrets file:

```bash
sops ../secrets/secrets.yaml
```

Add these two lines (SOPS will encrypt them automatically when you save):

```yaml
cloudflare_api_token: your-api-token-here
cloudflare_zone_id: your-zone-id-here
```

Save and exit. SOPS will encrypt the values.

### 3. Enter Development Shell

```bash
# From the repo root
nix develop
```

This gives you access to the `tofu` command.

### 4. Initialize OpenTofu

```bash
cd terraform
tofu init
```

This downloads the Cloudflare and SOPS providers.

### 5. Import Existing DNS Records

Your existing DNS records need to be imported into Terraform state. First, find the record IDs:

**Option A: Using Cloudflare Dashboard**
1. Go to DNS settings for dimensiondoor.xyz
2. Click on each A record to see its details
3. The record ID is in the URL or record details

**Option B: Using Cloudflare API**
```bash
# Set your API token
export CF_API_TOKEN="your-api-token"
export ZONE_ID="your-zone-id"

# List all DNS records
curl -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json" | jq '.result[] | {name: .name, id: .id, type: .type}'
```

Once you have the record IDs, import them:

```bash
# Import root domain record
tofu import cloudflare_record.root <record-id-for-dimensiondoor.xyz>

# Import git subdomain record
tofu import cloudflare_record.git <record-id-for-git.dimensiondoor.xyz>

# Import media subdomain record
tofu import cloudflare_record.media <record-id-for-media.dimensiondoor.xyz>
```

### 6. Verify Import

After importing, verify that Terraform recognizes the existing state:

```bash
tofu plan
```

**Expected output**: `No changes. Your infrastructure matches the configuration.`

If you see changes, the configuration doesn't match your existing records. Review and adjust `dns.tf` or `variables.tf` accordingly.

## Daily Workflow

### View Current State

```bash
tofu show
```

### Check What Will Change

```bash
tofu plan
```

### Apply Changes

```bash
tofu apply
```

Review the planned changes and type `yes` to confirm.

### View Outputs

```bash
tofu output
```

## Adding New DNS Records

1. Edit `dns.tf` and add a new resource:

```hcl
resource "cloudflare_record" "new_service" {
  zone_id = local.zone_id
  name    = "new"
  content = var.homeserver_ip
  type    = "A"
  proxied = var.cloudflare_proxied
  ttl     = 1
  comment = "New service - managed by Terraform"
}
```

2. Plan and apply:

```bash
tofu plan
tofu apply
```

## Modifying Records

### Change IP Address

Edit `variables.tf` or create `terraform.tfvars`:

```hcl
homeserver_ip = "new.ip.address"
```

Then apply:

```bash
tofu plan
tofu apply
```

### Toggle Cloudflare Proxy

```hcl
cloudflare_proxied = false  # or true
```

## File Structure

- `providers.tf` - Provider configuration (Cloudflare + SOPS)
- `variables.tf` - Input variables with defaults
- `dns.tf` - DNS record definitions
- `outputs.tf` - Output values after apply
- `terraform.tfvars.example` - Example variables file
- `.gitignore` - Excludes state files and sensitive data

## Troubleshooting

### Error: Invalid SOPS file

Make sure you've added the secrets to `../secrets/secrets.yaml` and they're properly encrypted.

### Error: Invalid credentials

Verify your API token has the correct permissions and hasn't expired.

### Error: Record already exists

You need to import the existing record first (see step 5 above).

### Drift Detection

If someone manually changes DNS in Cloudflare dashboard:

```bash
tofu plan  # Will show the drift
tofu apply # Will restore to desired state
```

## Current DNS Records

- `dimensiondoor.xyz` → 76.201.4.6 (proxied)
- `git.dimensiondoor.xyz` → 76.201.4.6 (proxied)
- `media.dimensiondoor.xyz` → 76.201.4.6 (proxied)

All records point to your homeserver and are proxied through Cloudflare for DDoS protection.

## Security Notes

- **Never commit** `terraform.tfvars` or state files to git (they're gitignored)
- API token is stored encrypted in SOPS
- State file contains record IDs but no sensitive credentials
- Cloudflare proxy hides your real IP address

## Resources

- [OpenTofu Documentation](https://opentofu.org/docs/)
- [Cloudflare Provider Docs](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs)
- [SOPS Provider Docs](https://registry.terraform.io/providers/carlpett/sops/latest/docs)
