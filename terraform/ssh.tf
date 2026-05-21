resource "hcloud_ssh_key" "admin" {
  count      = length(var.ssh_public_keys)
  name       = "foldforge-admin-${count.index}"
  public_key = var.ssh_public_keys[count.index]
}
