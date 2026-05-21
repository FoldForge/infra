# MVP: Postgres runs as a container on the app node (declared in cloud-init),
# bind-mounted to a Hetzner volume for durability. When scale demands it, swap
# this for a managed provider by replacing the volume + cloud-init block with a
# managed_database resource.
resource "hcloud_volume" "pg_data" {
  name     = "foldforge-pg-${var.environment}"
  size     = 50 # GB
  location = var.location
  format   = "ext4"
}

resource "hcloud_volume_attachment" "pg_data" {
  volume_id = hcloud_volume.pg_data.id
  server_id = hcloud_server.app.id
  automount = true
}
