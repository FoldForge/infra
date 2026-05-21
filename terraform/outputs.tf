output "app_ipv4" {
  description = "Public IPv4 of the app node"
  value       = hcloud_server.app.ipv4_address
}

output "app_private_ip" {
  value = "10.10.1.10"
}

output "artifacts_bucket" {
  value = cloudflare_r2_bucket.artifacts.name
}

output "msa_cache_bucket" {
  value = cloudflare_r2_bucket.msa_cache.name
}

output "pg_volume_id" {
  value = hcloud_volume.pg_data.id
}
