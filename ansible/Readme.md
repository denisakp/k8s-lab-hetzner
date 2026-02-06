# Ansible Configuration

Universal infrastructure-as-code setup for Ubuntu 24.04 VMs created by Terraform.

This Ansible playbook handles:
- ✅ User management (ansible-deploy, zanzibar)
- ✅ Base packages, timezone, keyboard layout
- ✅ SSH firewall (fail2ban-protected)
- ✅ Fail2Ban (brute-force protection)

**This Ansible setup does NOT know or care about Kubernetes.** VMs can be used for any purpose.

For Kubernetes deployment on these prepared VMs, use [Kubespray](https://kubespray.io/) with its own inventory and configuration.

## Structure

```txt
ansible/
├── ansible.cfg              # Ansible configuration
├── inventory/
│   └── hosts.yml           # VM inventory (Terraform-provisioned)
├── group_vars/
│   └── all.yml             # Common variables (timezone, packages, firewall)
├── playbooks/
│   ├── site.yml                  # 🎯 MAIN: Infrastructure setup (run this)
│   ├── common.yml                # Universal setup for all VMs
│   ├── setup.yml                 # Legacy (no longer used)
│   └── test.yml                  # Testing playbook
└── roles/
    ├── user_management/    # Create ansible-deploy, zanzibar users + sudo
    ├── commons/            # Base packages, timezone, keyboard
    ├── fail2ban/           # SSH brute-force protection
    └── firewalld/          # SSH-only firewall
```

Note: Deprecated files in `group_vars/` and `playbooks/`:
- `k8s_cluster.yml`, `k8s_control_plane.yml`, `k8s_workers.yml` - ⚠️ Use Kubespray's inventory instead
- `k8s-hardening.yml` - ⚠️ Kubespray handles Kubernetes hardening
- `pre-kubespray-verify.yml` - ⚠️ Use Kubespray's validation
- `post-kubespray-verify.yml` - ⚠️ Use Kubespray's validation

## Prerequisites

- Ubuntu 24.04 VMs provisioned by Terraform (see [../terraform/Readme.md](../terraform/Readme.md))
- SSH access with ED25519 key (configured in inventory)
- Python 3 installed on target hosts
- SSH ProxyJump configured for private network access (see [Network Access](#network-access))

## Roles

### user_management

- Creates `ansible-deploy` user with limited sudo access
- Creates `zanzibar` user with full sudo access

- Creates `zanzibar` user with full sudo access (management)
- Distributes ED25519 SSH keys to both users
- Configures `/etc/sudoers.d` safely with validation

### commons

- Updates system packages
- Installs common tools (vim, curl, wget, etc.)
- Configures timezone
- Sets keyboard layout (Ubuntu-compatible)

### fail2ban

- Installs Fail2Ban (intrusion detection/prevention)
- Protects SSH from brute-force attacks
- Bans offending IPs after configurable retry limit
- Sends notifications on ban events

### firewalld

- Installs and enables firewalld
- Allows SSH service (fail2ban protects against brute-force)
- Denies all other inbound traffic by default
- Internal K8s network traffic is managed by Kubespray (via iptables)

### fail2ban

- Installs and configures Fail2Ban
- Protects SSH from brute-force attacks
- Bans offending IPs after configurable retry limit
- Integration: Firewalld uses fail2ban for SSH protection

### firewalld

- Installs and enables firewalld
- Allows SSH service (fail2ban protects against brute-force)
- Denies all other inbound traffic by default
- Can be extended for specific services/ports (see Variables)

## Usage

### Run infrastructure setup (recommended)

```bash
cd ansible

# Setup all VMs
ansible-playbook playbooks/site.yml

# Setup specific group
ansible-playbook playbooks/site.yml --limit bastion
```

### Run specific playbooks

**Only base configuration (common.yml):**
```bash
ansible-playbook playbooks/common.yml
```

### Test connectivity

```bash
# Test all VMs
ansible all -m ping

# Test specific VMs
ansible vms -m ping
```

### Syntax validation

```bash
ansible-playbook playbooks/site.yml --syntax-check
ansible-playbook playbooks/common.yml --syntax-check
```

### Dry run

```bash
ansible-playbook playbooks/site.yml --check --diff
```

## Verification

After running playbooks, verify installation:

```bash
# Check users were created
ansible all -m ansible.builtin.command -a "id ansible-deploy"
ansible all -m ansible.builtin.command -a "id zanzibar"

# Check sudoers
ansible all -m ansible.builtin.command -a "cat /etc/sudoers.d/ansible-deploy" -b

# Check fail2ban
ansible all -m ansible.builtin.command -a "sudo fail2ban-client status sshd"

# Check firewall
ansible all -m ansible.builtin.command -a "sudo firewall-cmd --list-services"
```

## Why Ansible doesn't mention Kubernetes

This Ansible setup is **universal infrastructure provisioning**:
- ✅ Works for any VM purpose (K8s nodes, app servers, databases, etc.)
- ✅ Terraform creates VMs without knowing their purpose
- ✅ Ansible prepares VMs universally
- ✅ Kubernetes is deployed AFTER infrastructure is ready (via Kubespray)

This separation of concerns ensures:
- **Flexibility**: Same VMs can be repurposed
- **Simplicity**: Ansible doesn't assume node roles
- **Maintainability**: Infrastructure and Kubernetes config are independent

## Kubespray Deployment (Optional)

If you want to deploy Kubernetes on these prepared VMs, use Kubespray:

```bash
# Clone Kubespray
cd ..
git clone https://github.com/kubernetes-sigs/kubespray.git
cd kubespray

# Kubespray will handle:
# ✅ Swap disable
# ✅ Kernel module loading
# ✅ Sysctl tuning
# ✅ Container runtime (containerd)
# ✅ Kubernetes cluster initialization
# ✅ CNI plugin configuration

# Deploy
ansible-playbook -i ../ansible/inventory/hosts.yml cluster.yml
```

See [Kubespray Documentation](https://kubespray.io/) for full setup options.

## Playbook Reference

### Run against specific hosts

**All VMs:**
```bash
ansible-playbook playbooks/site.yml
```

**Only bastion:**
```bash
ansible-playbook playbooks/site.yml --limit bastion
```

**Run individual roles**

**Only setup users:**
```bashansible-playbook playbooks/common.yml
```

### Run against specific host groups

**All VMs (base configuration):**
```bash
ansible-playbook playbooks/site.yml
```

**Only Kubernetes nodes:**
```bash
ansible-playbook playbooks/site.yml --limit k8s_cluster
```

**Only control plane nodes:**
```bash
ansible-playbook playbooks/site.yml --limit k8s_control_plane
```

**Only worker nodes:**
```bash
ansible-playbook playbooks/site.yml --limit k8s_workers
```

**Only bastion:**
```bash
ansible-playbook playbooks/common.yml --limit bastion
```

**Only proxmox hosts:**
```bash
ansible-playbook playbooks/common.yml --limit proxmox_hosts
```

### Run individual roles

**Only setup users (no security changes):**
```bash
ansible-playbook playbooks/site.yml --tags user_management
```

**Only firewall (no kernel changes):**
```bash
ansible-playbook playbooks/site.yml --tags firewall
```

### Syntax validation and testing

**Validate playbook syntax:**
```bash
ansible-playbook playbooks/site.yml --syntax-check
ansible-playbook playbooks/common.yml --syntax-check
ansible-playbook playbooks/pre-kubespray-verify.yml --syntax-check
ansible-playbook playbooks/post-kubespray-verify.yml --syntax-check
```

**Test connectivity:**
```bash
ansible all -m ping
ansible vms -m ping
ansible k8s_cluster -m ping
```

**Dry run (no changes):**
```bash
ansible-playbook playbooks/site.yml --check
ansible-playbook playbooks/common.yml --check --diff
```

## Pre & Post Kubespray Verification

### Before Kubespray (verify prerequisites)

```bash
# Check all prerequisites are met
ansible-playbook playbooks/pre-kubespray-verify.yml

# Expected output:
# ✅ Pre-Kubespray Verification Complete
# Python: Python 3.x.x
# User: ansible-deploy
# CPU Cores: N
```

### After Kubespray (verify deployment)

```bash
# Verify Kubespray deployment succeeded
ansible-playbook playbooks/post-kubespray-verify.yml

# Expected output:
# ✅ Post-Kubespray Verification Results
# Swap: Disabled ✅
# Kernel Modules:
#   - overlay: ✅
#   - br_netfilter: ✅
# ...
```

## Post-Deployment Verification

After running playbooks and Kubespray, verify success:

```bash
# Check users were created
ansible vms -m ansible.builtin.command -a "id ansible-deploy"
ansible vms -m ansible.builtin.command -a "id zanzibar"

# Check sudoers configuration
ansible vms -m ansible.builtin.command -a "cat /etc/sudoers.d/ansible-deploy"

# Check fail2ban status
ansible vms -m ansible.builtin.command -a "sudo fail2ban-client status sshd"

# Check firewall rules (SSH only for external access)
ansible vms -m ansible.builtin.command -a "sudo firewall-cmd --list-services"

# Test Kubernetes cluster access (from control plane)
ansible k8s_control_plane -m ansible.builtin.command -a "kubectl get nodes"
ansible k8s_control_plane -m ansible.builtin.command -a "kubectl get pods -A"
```

## Kubespray Integration

### Overview

**Kubespray** is a production-ready Kubernetes installer that handles:

- ✅ Container runtime (containerd)
- ✅ Kubernetes binaries (kubelet, kubeadm, kubectl)
- ✅ Swap disabling
- ✅ Kernel module configuration
- ✅ Sysctl tuning
- ✅ Cluster initialization and node joining
- ✅ CNI plugin (Calico, Cilium, Flannel, etc.)
- ✅ etcd, CoreDNS, kube-proxy deployment

**Our Ansible playbooks** handle everything BEFORE Kubespray:

- ✅ User creation (ansible-deploy, zanzibar)
- ✅ Base packages and system configuration
- ✅ SSH hardening and fail2ban
- ✅ Firewall (SSH access)

### Kubespray Variables

Our [group_vars/k8s_cluster.yml](group_vars/k8s_cluster.yml) provides variables for Kubespray:

```yaml
# Kubernetes version
k8s_version: "1.29.0"

# Container runtime
container_runtime: containerd

# Network configuration (used by Kubespray for CNI)
pod_network_cidr: "10.244.0.0/16"
service_cidr: "10.96.0.0/12"
```

You can override these variables when running Kubespray:

```bash
ansible-playbook -i inventory/hosts.yml kubespray/cluster.yml \
  -e kube_version=1.29.0 \
  -e kube_pods_subnet=10.244.0.0/16
```

### Why Kubespray handles K8s configuration

To avoid conflicts and simplify deployment:

| Configuration | Who handles | Reason |
|---|---|---|
| Swap disable | Kubespray | Consistent with K8s deployment automation |
| Kernel modules | Kubespray | Verified as part of deployment verification |
| Sysctl settings | Kubespray | Integrated with CNI plugin requirements |
| Container runtime | Kubespray | Runtime-specific configuration needed |
| CNI plugin | Kubespray | Integrated with cluster init |
| Firewall (K8s ports) | Kubespray (iptables) | Internal cluster communication |
| Firewall (SSH) | Our Ansible | External access control |
| User management | Our Ansible | Pre-deployment access setup |

This separation ensures:
- 🎯 Single responsibility (Ansible = access, Kubespray = K8s)
- 🔄 Idempotent configuration (no conflicting rules)
- ✅ Verified deployment (Kubespray validation built-in)

## Troubleshooting

### SSH connection fails

Ensure:
- SSH key path is correct in [inventory/hosts.yml](inventory/hosts.yml)
- Remote user matches VM configuration
- Target VMs are reachable (ping test)
- ProxyJump is configured in `~/.ssh/config`

```bash
ansible all -m ping
ansible vms -m ping
```

### Users Not Created

```bash
# Check if users exist
ansible vms -m ansible.builtin.command -a "getent passwd ansible-deploy"

# Re-run user_management role only
ansible-playbook playbooks/common.yml --tags user_management
```

### SSH Key Distribution Failed

```bash
# Manual key copy for ansible-deploy
ansible vms -m ansible.builtin.authorized_key -b \
  -a "user=ansible-deploy key='{{ lookup(\"file\", \"~/.ssh/id_ed25519.pub\") }}' state=present"
```

### Fail2Ban not starting

Check logs:
```bash
ansible vms -m ansible.builtin.command -a "systemctl status fail2ban" -b
ansible vms -m ansible.builtin.command -a "journalctl -u fail2ban -n 20" -b
```

### Firewall blocks legitimate traffic

```bash
# List current rules
ansible k8s_cluster -m ansible.builtin.command -a "firewall-cmd --list-all" -b

# Temporarily allow a port
ansible k8s_cluster -m ansible.builtin.command -a "firewall-cmd --add-port=8000/tcp --permanent && firewall-cmd --reload" -b
```

### Kubernetes Prerequisites Not Met

These checks should pass AFTER Kubespray deployment:

```bash
# Check swap is disabled (should be empty output)
ansible k8s_cluster -m ansible.builtin.command -a "swapon --show"

# Check kernel modules
ansible k8s_cluster -m ansible.builtin.command -a "lsmod | grep -E 'overlay|br_netfilter'"

# Check sysctl
ansible k8s_cluster -m ansible.builtin.command -a "sysctl net.ipv4.ip_forward"

# If any check fails, re-run Kubespray deployment:
# ansible-playbook -i inventory/hosts.yml kubespray/cluster.yml
```

### Kubespray Deployment Failed

1. Check inventory variables match your environment
2. Verify all nodes marked as `in_k8s_cluster` in inventory
3. Ensure Python 3 installed on all nodes
4. Check network connectivity between nodes
5. Consult [Kubespray troubleshooting guide](https://kubespray.io/)

## Security Notes

- SSH port is protected by Fail2Ban (no rate limiting in firewall)
- Default deny policy: Only explicitly allowed traffic passes
- Fail2Ban recidivism protection: Longer bans for repeat offenders
- All configuration changes are persistent (survives reboot)

## Integration with Terraform

VMs created by Terraform can be automatically added to Ansible:

```bash
# Generate inventory from Terraform output
terraform -chdir=../terraform output -json units_infos | jq -r '.[] | .ip_address' > ips.txt
```

Then manually add to [inventory/hosts.yml](inventory/hosts.yml) with your own IPs and usernames.

## Network Access

### SSH ProxyJump Configuration

Private VMs are behind Proxmox NAT. To access them directly from your local machine, configure SSH ProxyJump through the Proxmox host and bastion.

**Step 1: Create/edit `~/.ssh/config`:**

Replace placeholders with your actual values:

- `<PROXMOX_IP>` : Public IP of your Proxmox host
- `<PROXMOX_USER>` : SSH user on Proxmox (typically `root`)
- `<BASTION_IP>` : Private IP of bastion VM
- `<BASTION_USER>` : SSH user on bastion
- `<PRIVATE_NETWORK>` : Your private network range (e.g., `10.0.0.*`)
- `<VM_USER>` : SSH user on private VMs
- `<SSH_KEY>` : Path to your ED25519 SSH key

```ssh-config
Host proxmox
  HostName <PROXMOX_IP>
  User <PROXMOX_USER>
  IdentityFile <SSH_KEY>

Host bastion
  HostName <BASTION_IP>
  User <BASTION_USER>
  IdentityFile <SSH_KEY>
  ProxyJump proxmox

Host <PRIVATE_NETWORK>
  User <VM_USER>
  IdentityFile <SSH_KEY>
  ProxyJump bastion
```

**Example** (adapt to your setup):

```ssh-config
Host proxmox
  HostName 192.168.1.10
  User root
  IdentityFile ~/.ssh/id_ed25519

Host bastion
  HostName 10.0.0.11
  User ubuntu
  IdentityFile ~/.ssh/id_ed25519
  ProxyJump proxmox

Host 10.0.0.*
  User ubuntu
  IdentityFile ~/.ssh/id_ed25519
  ProxyJump bastion
```

**Step 2: Distribute SSH keys**

Copy your key to bastion (through Proxmox):

```bash
ssh-copy-id -o ProxyJump=<PROXMOX_USER>@<PROXMOX_IP> <BASTION_USER>@<BASTION_IP>
```

Copy key to private VMs (through double jump):

```bash
ssh-copy-id -o ProxyJump="<PROXMOX_USER>@<PROXMOX_IP>,<BASTION_USER>@<BASTION_IP>" <VM_USER>@<PRIVATE_VM_IP>
# Repeat for each VM
```

**Step 3: Update Ansible inventory**

Edit [inventory/hosts.yml](inventory/hosts.yml) - SSH ProxyJump is now configured in `~/.ssh/config`, so Ansible will use it automatically.

**Test connection:**

```bash
ansible all -i inventory/hosts.yml -m ping
```

**Network flow:**

```txt
Local PC → Proxmox (<PROXMOX_IP>) → Bastion (<BASTION_IP>) → Private VMs (<PRIVATE_NETWORK>)
```
## Next Steps: RBAC and Access Management

After Kubespray successfully deploys Kubernetes, configure RBAC to secure cluster access.

### Generate Non-Admin kubeconfig

⚠️ **Security Best Practice**: Never expose admin kubeconfig (`/etc/kubernetes/admin.conf`)

Instead, create a non-admin ServiceAccount:

```bash
# SSH to control plane node (via bastion + ProxyJump)
ssh <CONTROL_PLANE_IP>

# Create ServiceAccount for non-admin user (e.g., developer)
kubectl create serviceaccount <USERNAME> -n default

# Create Role with minimal permissions
kubectl create role <ROLE_NAME> \
  --verb=get,list,watch \
  --resource=pods,services,deployments \
  -n default

# Bind ServiceAccount to Role
kubectl create rolebinding <USERNAME>-binding \
  --role=<ROLE_NAME> \
  --serviceaccount=default:<USERNAME> \
  -n default

# Extract token and CA cert for kubeconfig
TOKEN=$(kubectl get secret $(kubectl get secret -n default | grep <USERNAME> | awk '{print $1}') -n default -o jsonpath='{.data.token}' | base64 -d)
CACERT=$(kubectl get secret $(kubectl get secret -n default | grep <USERNAME> | awk '{print $1}') -n default -o jsonpath='{.data.ca\.crt}')
API_SERVER=$(kubectl cluster-info | grep 'Kubernetes master' | awk '/https/ {print $7}')
```

### Manage Cluster Users with Ansible

Once RBAC is in place, automate ServiceAccount creation via new Ansible role:

```bash
# Create role for RBAC management
mkdir -p roles/k8s_rbac/tasks

# Develop playbook for ServiceAccount creation
# See: https://github.com/kubernetes-sigs/kubespray/tree/master/roles/kubernetes/kubespray-defaults
```

### Recommended Access Pattern

```
Local Machine
  ├─ Admin: kubeadm reset, kubelet restart, CNI updates (direct SSH to control plane)
  └─ Developers: kubectl apply, get logs, view metrics (ServiceAccount + kubeconfig)
```

All access via:
- SSH ProxyJump (Proxmox → Bastion → Nodes)
- Fail2Ban protection on all nodes
- Non-root ansible-deploy user with minimal sudo