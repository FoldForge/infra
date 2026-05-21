# MVP topology: a single app node runs gateway + orchestrator via docker compose.
# GPU sidecars run on rented GPU hosts (RunPod/Lambda/Hetzner GEX) wired in a
# later phase; for now their endpoints are configured manually.
resource "hcloud_server" "app" {
  name        = "foldforge-app-${var.environment}"
  server_type = var.app_server_type
  image       = "docker-ce" # Hetzner app image with Docker preinstalled
  location    = var.location
  ssh_keys    = hcloud_ssh_key.admin[*].id
  firewall_ids = [hcloud_firewall.app.id]

  network {
    network_id = hcloud_network.core.id
    ip         = "10.10.1.10"
  }

  labels = {
    role        = "app"
    environment = var.environment
  }

  user_data = file("${path.module}/cloud-init/app.yaml")
}
