output "units_infos" {
  description = "Units provisioned"
  value = {
    for k, vm in proxmox_vm_qemu.nodes : k => {
      name       = vm.name
      id         = vm.id
      state      = vm.vm_state
      ip_address = split("/", split("ip=", vm.ipconfig0)[1])[0]
      macaddress = vm.network[0].macaddr
    }
  }
}

output "lxcs_info" {
  description = "LXC containers provisioned"
  value = {
    for k, lxc in proxmox_lxc.lcxs : k => {
      hostname   = lxc.hostname
      id         = lxc.id
      start      = lxc.start
      ip_address = split("/", lxc.network[0].ip)[0]
      macaddress = lxc.network[0].hwaddr
    }
  }
}