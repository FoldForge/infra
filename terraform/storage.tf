# Object storage for artifact exchange (PDB/CIF/MSA blobs) and the AF2 MSA cache.
resource "cloudflare_r2_bucket" "artifacts" {
  account_id = var.cloudflare_account_id
  name       = "foldforge-artifacts-${var.environment}"
  location   = "WEUR"
}

resource "cloudflare_r2_bucket" "msa_cache" {
  account_id = var.cloudflare_account_id
  name       = "foldforge-msa-cache-${var.environment}"
  location   = "WEUR"
}

# Terraform remote-state bucket is bootstrapped out-of-band (chicken/egg) — see
# README. Declared here for documentation/import.
# resource "cloudflare_r2_bucket" "tfstate" { ... }
