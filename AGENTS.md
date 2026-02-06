# AGENTS.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

Homelab infrastructure-as-code repository for provisioning and managing VMs on Proxmox using Terraform, with planned Ansible configuration management.

## Architecture

```txt
homelab/
├── terraform/     # Proxmox VM provisioning via Telmate provider
├── ansible/       # Configuration management (placeholder)
└── proxmox/       # Proxmox host setup documentation
```

### Terraform Configuration

- **Provider**: `telmate/proxmox` (3.0.2-rc06) for Proxmox VE API
- **Backend**: Terraform Cloud (org: `akpagnonited`, workspace: `homelab`)
- **VM Pattern**: Cloud-init based QEMU VMs cloned from a template (`ubuntu-cloud-init-template` by default)
- **Output**: `units_ips` output is designed for Ansible inventory consumption

### Required Variables (via .tfvars - gitignored)

| Variable | Purpose |
|----------|---------|
| `api_url` | Proxmox API URL |
| `token_id` | Proxmox API user |
| `token_secret` | Proxmox API password/token |
| `node` | Target Proxmox node name |
| `node_units` | Map of VMs to provision (name, ciuser, cipassword, macaddress, etc.) |

## Commands

### Terraform

```bash
# Initialize (from terraform/ directory)
terraform init

# Plan changes
terraform plan -var-file=secrets.tfvars

# Apply changes
terraform apply -var-file=secrets.tfvars

# Get VM IPs for Ansible
terraform output -json units_ips
```

## Proxmox Setup

See `proxmox/Readme.md` for creating the Terraform service account with required permissions (`TerraformRole`).
