variable "hcloud_token" {
  description = "Hetzner Cloud API token"
  type        = string
  sensitive   = true
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with R2 edit permission"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID (for R2 buckets)"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "mvp"
}

variable "location" {
  description = "Hetzner location"
  type        = string
  default     = "nbg1" # Nuremberg
}

variable "app_server_type" {
  description = "Hetzner server type for gateway + orchestrator (CPU)"
  type        = string
  default     = "cpx31" # 4 vCPU / 8GB
}

variable "ssh_public_keys" {
  description = "SSH public keys granted access to provisioned servers"
  type        = list(string)
}

variable "postgres_version" {
  description = "Managed Postgres major version"
  type        = string
  default     = "16"
}
