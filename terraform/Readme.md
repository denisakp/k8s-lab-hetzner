# Terraform Configuration

This folder provisions Proxmox resources using Terraform:
- **QEMU VMs**: Cloned from a Cloud-Init template (see [proxmox/Readme.md#cloud-init-preparation](../proxmox/Readme.md#cloud-init-preparation)). Terraform injects Cloud-Init settings (user, SSH keys, IP, etc.).
- **LXC Containers**: Created from an OS template (downloaded via `pveam`). Lightweight alternative to VMs for containerized workloads.

## Prerequisites

- A Proxmox host with:
  - A Cloud-Init template VM for QEMU VMs (see [proxmox/Readme.md#cloud-init-preparation](../proxmox/Readme.md#cloud-init-preparation))
  - LXC OS templates downloaded via `pveam` (e.g., `ubuntu-24.04-standard`)
- A Proxmox API user and token with the required permissions (see [proxmox/Readme.md#creating-the-proxmox-user-and-role-for-terraform](../proxmox/Readme.md#creating-the-proxmox-user-and-role-for-terraform))
- Terraform installed locally

## Backend: Terraform Cloud

This repo is configured to use Terraform Cloud in [backend.tf](backend.tf). To use it:

```bash
cd terraform
terraform login
terraform init
```

I use a local `terraform.tfvars` file, but it is recommended to set the variables in Terraform Cloud (Workspace Variables) for `proxmox_api_url`, `proxmox_token_id`, `proxmox_token_secret`, and `node_units`. Mark sensitive values as sensitive.

## Backend: Local state (optional)

If you prefer local state, edit [backend.tf](backend.tf) and disable the `cloud` block (or switch to the local backend). Then reinitialize:

```bash
cd terraform
terraform init
```

## Configuration

The main inputs are in [terraform.tfvars](terraform.tfvars). Do not commit secrets.

Example:

```hcl
api_url      = "https://<PROXMOX_IP>:8006/api2/json"
token_id     = "terraform@pve!terraform-token"
token_secret = "<PROXMOX_API_TOKEN>"
node         = "pve1"

# QEMU VMs
node_units = {
    alpha = {
        name      = "alpha"
        ipconfig0 = "ip=10.0.0.100/24,gw=10.0.0.1"
        ciuser    = "ubuntu"
        cipassword = "<PASSWORD>"
        sshkeys   = "<SSH_PUBLIC_KEY>"
        # optional: cores, memory, disk_size
    }
}

# LXC Containers
lxc_units = {
    beta = {
        hostname = "beta"
        ip       = "10.0.0.101/24"
        gw       = "10.0.0.1"
        password = "<PASSWORD>"
        # optional: cores, memory, rootfs_size, ostemplate, ssh_public_keys
    }
}
```

### Static IPs

**QEMU VMs (Cloud-Init format)**:
Set `ipconfig0` in `node_units`:
```text
ipconfig0 = "ip=10.0.0.100/24,gw=10.0.0.1"
```

**LXC Containers**:
Set `ip` and `gw` separately:
```hcl
ip = "10.0.0.101/24"
gw = "10.0.0.1"
```

## Commands

```bash
cd terraform

# Validate configuration
terraform validate

# Plan changes (local state)
terraform plan -var-file=terraform.tfvars

# Apply changes (local state)
terraform apply -var-file=terraform.tfvars
```

## Outputs

After apply, Terraform exposes:

- **`units_infos`**: QEMU VMs (name, id, state, IP, MAC address)
- **`lxcs_info`**: LXC containers (hostname, id, start status, IP, MAC address)

```bash
terraform output
terraform output -json units_infos
terraform output -json lxcs_info
```

## Notes

- **QEMU VMs**: The Cloud-Init template name is defined by `clone_name` in [variables.tf](variables.tf). Ensure it matches your template VM.
- **LXC Containers**: The OS template is defined by `ostemplate` (default: `ubuntu-24.04-standard_24.04-2_amd64.tar.zst`).
- This repo intentionally omits secrets. Use a local `terraform.tfvars` (gitignored) and/or Terraform Cloud sensitive variables.
- All resources are attached to `vmbr1` (private bridge with NAT).
