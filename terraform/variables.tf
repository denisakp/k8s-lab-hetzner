variable "proxmox_api_url" {
  description = "Proxmox API url"
  type        = string
}

variable "proxmox_token_id" {
  description = "Proxmox API token ID"
  type        = string
}

variable "proxmox_token_secret" {
  description = "Proxmox API token secret"
  type        = string
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "pve1"
}

variable "clone_name" {
  description = "Proxmox cloud init template name"
  type        = string
  default     = "ubuntu-2404-cloudinit-template"
}

variable "node_units" {
  description = "Map of nodes to provision"

  type = map(object({
    name       = string
    ciuser     = string
    cipassword = string
    ipconfig0  = string
    cores      = optional(number, 2)
    memory     = optional(number, 4096)
    disk_size  = optional(string, "10G")
    sshkeys    = optional(string, "")
  }))
}

variable "lxc_units" {
  description = "Map of CT to provision"

  type = map(object({
    hostname  = string
    disk_size = optional(string, "8G")
    ipaddress = string
    gw        = string
    sshkeys   = optional(string, null)
    password  = optional(string, null)
  }))
}