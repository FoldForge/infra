# Private network so gateway <-> orchestrator <-> (future GPU sidecars) traffic
# never leaves Hetzner's backbone.
resource "hcloud_network" "core" {
  name     = "foldforge-${var.environment}"
  ip_range = "10.10.0.0/16"
}

resource "hcloud_network_subnet" "app" {
  network_id   = hcloud_network.core.id
  type         = "cloud"
  network_zone = "eu-central"
  ip_range     = "10.10.1.0/24"
}

resource "hcloud_firewall" "app" {
  name = "foldforge-app-${var.environment}"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}
