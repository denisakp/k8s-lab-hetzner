# Ansible Configuration

This folder configures Ubuntu 24 VMs using Ansible roles. It applies security hardening with **firewalld** and **fail2ban**.

## Structure

```txt
ansible/
├── ansible.cfg              # Ansible configuration
├── inventory/
│   └── hosts.yml           # Inventory of target hosts
├── group_vars/
│   └── all.yml             # Variables for all hosts
├── playbooks/
│   ├── setup.yml           # Main playbook (commons, fail2ban, firewalld)
│   └── test.yml            # Test playbook
└── roles/
    ├── commons/            # Common setup (packages, timezone, etc.)
    ├── fail2ban/           # Fail2Ban IDS/brute-force protection
    └── firewalld/          # Firewall management
```

## Prerequisites

- Ubuntu 24.04 VMs provisioned by Terraform (see [../terraform/Readme.md](../terraform/Readme.md)) using Cloud-Init templates (see [../proxmox/Readme.md#cloud-init-preparation](../proxmox/Readme.md#cloud-init-preparation))
- SSH access with ED25519 key (configured in inventory)
- Python 3 installed on target hosts
- SSH ProxyJump configured for private network access (see [Network Access](#network-access))

## Configuration

### Inventory Setup

Edit [inventory/hosts.yml](inventory/hosts.yml) to add your VMs. Replace placeholders with your actual values:

```yaml
all:
  hosts:
    # Replace <VM_NAME> with your VM hostname
    # Replace <PRIVATE_VM_IP> with actual VM IP (e.g., 10.0.0.100)
    # Replace <VM_USER> with actual user (e.g., ubuntu, zanzibar)
    # Replace <SSH_KEY_PATH> with path to your ED25519 key
    <VM_NAME>:
      ansible_host: <PRIVATE_VM_IP>
      ansible_user: <VM_USER>
      ansible_ssh_private_key_file: <SSH_KEY_PATH>
```

**Example** (adapt to your setup):
```yaml
all:
  hosts:
    my-vm-1:
      ansible_host: 10.0.0.100
      ansible_user: ubuntu
      ansible_ssh_private_key_file: ~/.ssh/id_ed25519
```

### Variables

Edit [group_vars/all.yml](group_vars/all.yml) to customize:

- **timezone** : System timezone (default: UTC)
- **common_packages** : Packages to install
- **fail2ban_** : Fail2Ban ban times and retry limits
- **firewall_allowed_services** : Services to allow (ssh, http, https)
- **firewall_allowed_ports** : Additional ports to allow

Example custom ports:

```yaml
firewall_allowed_ports:
  - "<CUSTOM_PORT>/tcp"     # Your port forwarding rules
  - "<ANOTHER_PORT>/tcp"    # Add as needed
```

## Roles

### commons

- Updates system packages
- Installs common tools (vim, curl, wget, etc.)
- Configures timezone
- Sets keyboard layout

### fail2ban

- Installs Fail2Ban (intrusion detection/prevention)
- Protects SSH from brute-force attacks
- Bans offending IPs after configurable retry limit
- Sends notifications on ban events

Default settings:

- Ban duration: 1 day
- Ban (recidive): 30 days  
- Max retries before ban: 3

### firewalld

- Installs and enables firewalld
- Allows configured services (SSH, HTTP, HTTPS by default)
- Allows custom ports
- Denies all other inbound traffic

## Usage

### Run the full setup playbook:

```bash
cd ansible

# Validate playbook syntax
ansible-playbook playbooks/setup.yml --syntax-check

# Run on all hosts
ansible-playbook playbooks/setup.yml

# Run on specific host
ansible-playbook playbooks/setup.yml -i inventory/hosts.yml -l alpha
```

### Run individual roles:

```bash
# Only configure firewall
ansible-playbook playbooks/setup.yml --tags firewalld

# Only setup commons
ansible-playbook playbooks/setup.yml --tags commons
```

### Verify configuration:

```bash
# Check fail2ban status
ansible all -m ansible.builtin.command -a "fail2ban-client status"

# Check firewall rules
ansible all -m ansible.builtin.command -a "firewall-cmd --list-all"
```

## Troubleshooting

### SSH connection fails

Ensure:

- SSH key path is correct in [inventory/hosts.yml](inventory/hosts.yml)
- Remote user matches VM configuration
- Target VMs are reachable (ping test)

```bash
ansible all -i inventory/hosts.yml -m ping
```

### Fail2Ban not starting

Check logs:

```bash
ansible all -m ansible.builtin.command -a "systemctl status fail2ban"
ansible all -m ansible.builtin.command -a "journalctl -u fail2ban -n 20"
```

### Firewall blocks legitimate traffic

Temporarily allow ports:
```bash
ansible all -m ansible.builtin.command -a "firewall-cmd --add-port=8000/tcp --permanent"
ansible all -m ansible.builtin.command -a "firewall-cmd --reload"
```

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
