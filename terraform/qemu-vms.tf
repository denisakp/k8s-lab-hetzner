resource "proxmox_vm_qemu" "nodes" {
  for_each = var.node_units

  target_node        = var.proxmox_node
  name               = each.value.name
  clone              = var.clone_name
  full_clone         = true
  agent              = 1
  memory             = each.value.memory
  os_type            = "cloud-init"
  scsihw             = "virtio-scsi-single"
  bios               = "seabios"
  qemu_os            = "l26"
  boot               = "order=scsi0"
  vm_state           = "running"
  automatic_reboot   = true
  start_at_node_boot = true

  # cloud init config
  ciuser     = each.value.ciuser
  cipassword = each.value.cipassword
  sshkeys    = each.value.sshkeys
  ciupgrade  = true
  nameserver = "1.1.1.1 8.8.8.8"
  ipconfig0  = each.value.ipconfig0

  cpu {
    type    = "host"
    sockets = 1
    cores   = each.value.cores
  }

  network {
    id       = 0
    model    = "virtio"
    firewall = false
    bridge   = "vmbr1"
  }

  disks {
    scsi {
      scsi0 {
        disk {
          storage = "local-zfs"
          size    = each.value.disk_size
          asyncio = "threads"
        }
      }
    }
    ide {
      ide1 {
        cloudinit {
          storage = "local-zfs"
        }
      }
    }
  }

  vga {
    type   = "std"
    memory = 128
  }

  serial {
    id   = 0
    type = "socket"
  }

}
