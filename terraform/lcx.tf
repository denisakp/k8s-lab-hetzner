resource "proxmox_lxc" "lcxs" {
  for_each = var.lxc_units

  target_node     = var.proxmox_node
  hostname        = each.value.hostname
  password        = each.value.password
  ssh_public_keys = each.value.sshkeys

  #os template path
  ostemplate = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
  features {
    nesting = true
  }
  unprivileged = true
  ostype       = "ubuntu"

  cores  = 1
  memory = 1024
  swap   = 256

  start  = true
  onboot = true

  rootfs {
    storage = "local-zfs"
    size    = each.value.disk_size
  }

  network {
    bridge = "vmbr1"
    ip     = each.value.ipaddress
    gw     = each.value.gw
    name   = "eth0"
  }
}