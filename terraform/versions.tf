terraform {
  required_version = ">= 1.7"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.48"
    }
    # Cloudflare R2 buckets are managed via the Cloudflare provider.
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.40"
    }
  }

  # Remote state lives in R2 (S3-compatible). Configure via backend.hcl:
  #   terraform init -backend-config=backend.hcl
  backend "s3" {
    bucket                      = "foldforge-tfstate"
    key                         = "infra/terraform.tfstate"
    region                      = "auto"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    use_path_style              = true
  }
}
