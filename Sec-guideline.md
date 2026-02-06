# Kubernetes Lab Security Hardening Guide

## Overview

This guide provides step-by-step procedures to secure a Kubernetes lab environment deployed on Proxmox with a bastion host architecture. The security measures are designed for a personal/development environment while maintaining reasonable protection against common threats.

**Target Architecture:**

```
Internet → Proxmox (public IP) → Bastion (private) → K8s Nodes (private)
```

**Security Layers:**
1. Proxmox host hardening
2. WireGuard VPN access
3. Bastion host security
4. Kubernetes nodes firewall
5. RBAC-based access (no admin kubeconfig exposure)
6. Ansible automation user

---

## 1. Proxmox Host Security

### 1.1 Create Non-Root User

```bash
# SSH to Proxmox as root
ssh root@65.109.67.88

# Create admin user
useradd -m -s /bin/bash proxmox-admin
userpasswd proxmox-admin  # Set strong password

# Add to necessary groups
usermod -aG sudo proxmox-admin

# Copy SSH authorized_keys
mkdir -p /home/proxmox-admin/.ssh
cp /root/.ssh/authorized_keys /home/proxmox-admin/.ssh/
chown -R proxmox-admin:proxmox-admin /home/proxmox-admin/.ssh
chmod 700 /home/proxmox-admin/.ssh
chmod 600 /home/proxmox-admin/.ssh/authorized_keys
```

we should make sure to create the user also in proxmox so that he could connect to proxmox ui and manage the infrastructure. To do that, we need to create a user in proxmox with the same name and password as the one we created in linux using cli.


### 1.2 Harden SSH Configuration

```bash
# Edit SSH config
nano /etc/ssh/sshd_config

# Apply these settings:
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
AllowUsers proxmox-admin

# Restart SSH
systemctl restart sshd
```

**⚠️ CRITICAL:** Test new user login in a separate terminal **BEFORE** closing root session:
```bash
# From local machine
ssh proxmox-admin@65.109.67.88
```

### 1.3 Install and Configure fail2ban

```bash
apt update
apt install fail2ban -y

# Create local config
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
backend = systemd

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
EOF

# Enable and start
systemctl enable fail2ban
systemctl start fail2ban

# Check status
fail2ban-client status sshd
```

---

## 2. WireGuard VPN Setup

### 2.1 Install WireGuard on Proxmox

```bash
apt update
apt install wireguard -y

# Enable IP forwarding
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p
```

### 2.2 Generate Keys

```bash
cd /etc/wireguard
umask 077

# Server keys
wg genkey | tee server_private.key | wg pubkey > server_public.key

# Client keys (for your local machine)
wg genkey | tee client_private.key | wg pubkey > client_public.key

# Display keys for configuration
echo "Server Private: $(cat server_private.key)"
echo "Server Public: $(cat server_public.key)"
echo "Client Private: $(cat client_private.key)"
echo "Client Public: $(cat client_public.key)"
```

### 2.3 Configure WireGuard Server

```bash
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = 10.10.10.1/24
ListenPort = 51820
PrivateKey = <SERVER_PRIVATE_KEY>
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o vmbr0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o vmbr0 -j MASQUERADE

# Client peer (your local machine)
[Peer]
PublicKey = <CLIENT_PUBLIC_KEY>
AllowedIPs = 10.10.10.2/32
EOF

# Start WireGuard
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# Check status
wg show
```

### 2.4 Configure WireGuard Client (Local Machine)

**Linux/macOS:**
```bash
# Install WireGuard
# Ubuntu/Debian: sudo apt install wireguard
# macOS: brew install wireguard-tools

# Create client config
sudo nano /etc/wireguard/lab.conf

[Interface]
Address = 10.10.10.2/24
PrivateKey = <CLIENT_PRIVATE_KEY>
DNS = 1.1.1.1

[Peer]
PublicKey = <SERVER_PUBLIC_KEY>
Endpoint = 65.109.67.88:51820
AllowedIPs = 10.10.10.0/24, 10.0.0.0/24
PersistentKeepalive = 25

# Connect
sudo wg-quick up lab

# Verify
sudo wg show
ping 10.10.10.1
```

**Windows:** Use WireGuard GUI application with the same configuration.

### 2.5 Update SSH Config for WireGuard

```bash
# Edit ~/.ssh/config on local machine
nano ~/.ssh/config

Host proxmox
  HostName 10.10.10.1  # Use WireGuard IP
  User proxmox-admin
  IdentityFile ~/.ssh/id_ed25519

Host bastion
  HostName 10.0.0.11
  User zanzibar
  IdentityFile ~/.ssh/id_ed25519
  ProxyJump proxmox

Host 10.0.0.*
  User ansible-deploy
  IdentityFile ~/.ssh/id_ed25519
  ProxyJump bastion
```

### 2.6 Restrict SSH to VPN Only

```bash
# On Proxmox, edit SSH config
nano /etc/ssh/sshd_config

# Add at the end:
ListenAddress 10.10.10.1  # VPN interface only
ListenAddress 127.0.0.1   # Localhost

# Restart SSH
systemctl restart sshd
```

**⚠️ WARNING:** Ensure WireGuard is connected before applying this change, or you'll be locked out!

**Alternative (safer approach):** Use firewall rules:
```bash
# Allow SSH only from WireGuard
iptables -A INPUT -p tcp --dport 22 -s 10.10.10.0/24 -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j DROP

# Make persistent
apt install iptables-persistent
netfilter-persistent save
```

---

## 3. Bastion Host Hardening

### 3.1 Create Dedicated Users

```bash
# SSH to bastion
ssh bastion

# Create user for management
sudo useradd -m -s /bin/bash zanzibar
sudo usermod -aG sudo zanzibar
echo "zanzibar ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/zanzibar

# Create ansible user (limited privileges)
sudo useradd -m -s /bin/bash ansible-deploy
echo "ansible-deploy ALL=(ALL) NOPASSWD: /usr/bin/apt, /usr/bin/systemctl, /usr/bin/kubeadm, /usr/bin/kubectl" | sudo tee /etc/sudoers.d/ansible-deploy

# Copy SSH keys
sudo mkdir -p /home/zanzibar/.ssh
sudo mkdir -p /home/ansible-deploy/.ssh
sudo cp ~/.ssh/authorized_keys /home/zanzibar/.ssh/
sudo cp ~/.ssh/authorized_keys /home/ansible-deploy/.ssh/
sudo chown -R zanzibar:zanzibar /home/zanzibar/.ssh
sudo chown -R ansible-deploy:ansible-deploy /home/ansible-deploy/.ssh
sudo chmod 700 /home/{zanzibar,ansible-deploy}/.ssh
sudo chmod 600 /home/{zanzibar,ansible-deploy}/.ssh/authorized_keys
```

### 3.2 Harden SSH

```bash
sudo nano /etc/ssh/sshd_config

# Apply settings:
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AllowUsers zanzibar ansible-deploy

sudo systemctl restart sshd
```

### 3.3 Install fail2ban

```bash
sudo apt update
sudo apt install fail2ban -y

sudo cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
EOF

sudo systemctl enable fail2ban
sudo systemctl start fail2ban
```

---

## 4. Kubernetes Nodes Security

### 4.1 Prepare Ansible Playbook for Node Hardening

Create `playbooks/security-hardening.yml`:

```yaml
---
- name: Harden Kubernetes Nodes
  hosts: all
  become: yes
  tasks:
    - name: Create ansible-deploy user
      user:
        name: ansible-deploy
        shell: /bin/bash
        groups: sudo
        append: yes
        create_home: yes

    - name: Configure sudo for ansible-deploy
      copy:
        content: |
          ansible-deploy ALL=(ALL) NOPASSWD: /usr/bin/apt, /usr/bin/systemctl, /usr/bin/kubeadm, /usr/bin/kubectl, /usr/bin/crictl
        dest: /etc/sudoers.d/ansible-deploy
        mode: '0440'
        validate: 'visudo -cf %s'

    - name: Set up SSH key for ansible-deploy
      authorized_key:
        user: ansible-deploy
        key: "{{ lookup('file', '~/.ssh/id_ed25519.pub') }}"
        state: present

    - name: Harden SSH configuration
      lineinfile:
        path: /etc/ssh/sshd_config
        regexp: "{{ item.regexp }}"
        line: "{{ item.line }}"
      loop:
        - { regexp: '^PermitRootLogin', line: 'PermitRootLogin no' }
        - { regexp: '^PasswordAuthentication', line: 'PasswordAuthentication no' }
        - { regexp: '^PubkeyAuthentication', line: 'PubkeyAuthentication yes' }
        - { regexp: '^AllowUsers', line: 'AllowUsers ansible-deploy zanzibar' }
      notify: Restart SSH

    - name: Install UFW
      apt:
        name: ufw
        state: present
        update_cache: yes

    - name: Configure UFW - Allow SSH from bastion
      ufw:
        rule: allow
        from_ip: 10.0.0.11
        to_port: '22'
        proto: tcp

    - name: Configure UFW - Allow Kubernetes API
      ufw:
        rule: allow
        from_ip: 10.0.0.0/24
        to_port: '6443'
        proto: tcp

    - name: Configure UFW - Allow Kubelet API
      ufw:
        rule: allow
        from_ip: 10.0.0.0/24
        to_port: '10250'
        proto: tcp

    - name: Configure UFW - Allow NodePort Services
      ufw:
        rule: allow
        from_ip: 10.0.0.0/24
        to_port: '30000:32767'
        proto: tcp

    - name: Configure UFW - Default policies
      ufw:
        policy: "{{ item.policy }}"
        direction: "{{ item.direction }}"
      loop:
        - { direction: 'incoming', policy: 'deny' }
        - { direction: 'outgoing', policy: 'allow' }

    - name: Enable UFW
      ufw:
        state: enabled

    - name: Install fail2ban
      apt:
        name: fail2ban
        state: present

    - name: Configure fail2ban for SSH
      copy:
        content: |
          [DEFAULT]
          bantime = 3600
          findtime = 600
          maxretry = 3

          [sshd]
          enabled = true
          port = ssh
          logpath = /var/log/auth.log
        dest: /etc/fail2ban/jail.local
        mode: '0644'
      notify: Restart fail2ban

    - name: Ensure fail2ban is running
      systemd:
        name: fail2ban
        state: started
        enabled: yes

  handlers:
    - name: Restart SSH
      systemd:
        name: sshd
        state: restarted

    - name: Restart fail2ban
      systemd:
        name: fail2ban
        state: restarted
```

### 4.2 Create Ansible Inventory

Create `inventory/hosts.ini`:

```ini
[all:vars]
ansible_user=ubuntu
ansible_ssh_common_args='-o ProxyJump=zanzibar@10.0.0.11'

[k8s_masters]
master-01 ansible_host=10.0.0.100
master-02 ansible_host=10.0.0.101
master-03 ansible_host=10.0.0.102

[k8s_workers]
worker-01 ansible_host=10.0.0.110
worker-02 ansible_host=10.0.0.111
worker-03 ansible_host=10.0.0.112

[k8s_cluster:children]
k8s_masters
k8s_workers
```

### 4.3 Run Hardening Playbook

```bash
# From local machine
cd ~/k8s-lab
ansible-playbook -i inventory/hosts.ini playbooks/security-hardening.yml
```

### 4.4 Update SSH Config for Ansible User

```bash
# Update ~/.ssh/config
nano ~/.ssh/config

Host 10.0.0.*
  User ansible-deploy  # Changed from ubuntu
  IdentityFile ~/.ssh/id_ed25519
  ProxyJump bastion
```

---

## 5. Kubespray Deployment with Security

### 5.1 Clone Kubespray

```bash
git clone https://github.com/kubernetes-sigs/kubespray.git
cd kubespray
git checkout release-2.24  # Use latest stable
```

### 5.2 Prepare Inventory

```bash
# Copy sample inventory
cp -rfp inventory/sample inventory/mycluster

# Edit inventory
nano inventory/mycluster/hosts.yaml
```

Example `hosts.yaml`:
```yaml
all:
  hosts:
    master-01:
      ansible_host: 10.0.0.100
      ip: 10.0.0.100
    master-02:
      ansible_host: 10.0.0.101
      ip: 10.0.0.101
    master-03:
      ansible_host: 10.0.0.102
      ip: 10.0.0.102
    worker-01:
      ansible_host: 10.0.0.110
      ip: 10.0.0.110
    worker-02:
      ansible_host: 10.0.0.111
      ip: 10.0.0.111
    worker-03:
      ansible_host: 10.0.0.112
      ip: 10.0.0.112
  children:
    kube_control_plane:
      hosts:
        master-01:
        master-02:
        master-03:
    kube_node:
      hosts:
        worker-01:
        worker-02:
        worker-03:
    etcd:
      hosts:
        master-01:
        master-02:
        master-03:
    k8s_cluster:
      children:
        kube_control_plane:
        kube_node:
    calico_rr:
      hosts: {}
  vars:
    ansible_user: ansible-deploy
    ansible_ssh_common_args: '-o ProxyJump=zanzibar@10.0.0.11'
```

### 5.3 Configure Kubespray Security Settings

Edit `inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml`:

```yaml
# API server settings
kube_apiserver_enable_admission_plugins:
  - NodeRestriction
  - PodSecurityPolicy  # or use PodSecurity if K8s 1.25+
  - ServiceAccount

# Disable anonymous auth
kube_apiserver_anonymous_auth: false

# Enable audit logging
kubernetes_audit: true
audit_log_path: /var/log/kubernetes/audit.log
audit_log_maxage: 30
audit_log_maxbackup: 10
audit_log_maxsize: 100

# RBAC enabled
rbac_enabled: true

# Encrypt secrets at rest
kube_encrypt_secret_data: true

# Network plugin (Calico recommended for network policies)
kube_network_plugin: calico

# Enable network policies
enable_network_policy: true
```

### 5.4 Deploy Kubernetes

```bash
# Install dependencies
pip3 install -r requirements.txt

# Deploy cluster
ansible-playbook -i inventory/mycluster/hosts.yaml \
  --become --become-user=root \
  cluster.yml
```

### 5.5 Retrieve Kubeconfig Securely

```bash
# Create directory for kubeconfig on bastion
ssh bastion "mkdir -p ~/.kube"

# Copy from master to bastion
ssh bastion "ssh ansible-deploy@10.0.0.100 'sudo cat /etc/kubernetes/admin.conf' > ~/.kube/config"

# Copy from bastion to local
scp bastion:~/.kube/config ~/.kube/config-lab

# Set permissions
chmod 600 ~/.kube/config-lab

# Use it
export KUBECONFIG=~/.kube/config-lab
kubectl get nodes
```

---

## 6. RBAC Configuration (No Admin Access)

### 6.1 Create ServiceAccount for Deployments

```bash
# Set kubeconfig
export KUBECONFIG=~/.kube/config-lab

# Create namespace
kubectl create namespace production

# Create ServiceAccount
kubectl create serviceaccount deploy-user -n production
```

### 6.2 Create RBAC Role

Create `rbac/deploy-role.yaml`:

```yaml
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: deploy-role
  namespace: production
rules:
  # Deployments
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets", "statefulsets", "daemonsets"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  
  # Services
  - apiGroups: [""]
    resources: ["services"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  
  # ConfigMaps and Secrets
  - apiGroups: [""]
    resources: ["configmaps", "secrets"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  
  # Pods (read-only for troubleshooting)
  - apiGroups: [""]
    resources: ["pods", "pods/log"]
    verbs: ["get", "list", "watch"]
  
  # Ingress
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: deploy-user-binding
  namespace: production
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: deploy-role
subjects:
  - kind: ServiceAccount
    name: deploy-user
    namespace: production
```

Apply:
```bash
kubectl apply -f rbac/deploy-role.yaml
```

### 6.3 Generate Kubeconfig for ServiceAccount

Create script `scripts/generate-kubeconfig.sh`:

```bash
#!/bin/bash

SERVICE_ACCOUNT="deploy-user"
NAMESPACE="production"
CONTEXT=$(kubectl config current-context)
CLUSTER=$(kubectl config view -o jsonpath="{.contexts[?(@.name==\"$CONTEXT\")].context.cluster}")
SERVER=$(kubectl config view -o jsonpath="{.clusters[?(@.name==\"$CLUSTER\")].cluster.server}")

# Get secret name
SECRET_NAME=$(kubectl get sa $SERVICE_ACCOUNT -n $NAMESPACE -o jsonpath='{.secrets[0].name}')

# For K8s 1.24+, create token manually if secret doesn't exist
if [ -z "$SECRET_NAME" ]; then
    kubectl create token $SERVICE_ACCOUNT -n $NAMESPACE --duration=87600h > /tmp/token
    TOKEN=$(cat /tmp/token)
    rm /tmp/token
else
    TOKEN=$(kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.token}' | base64 -d)
fi

# Get CA certificate
CA_CERT=$(kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.ca\.crt}' 2>/dev/null || kubectl config view --raw -o jsonpath="{.clusters[?(@.name==\"$CLUSTER\")].cluster.certificate-authority-data}")

# Generate kubeconfig
cat > kubeconfig-deploy-user.yaml <<EOF
apiVersion: v1
kind: Config
clusters:
- name: ${CLUSTER}
  cluster:
    certificate-authority-data: ${CA_CERT}
    server: ${SERVER}
contexts:
- name: ${SERVICE_ACCOUNT}@${CLUSTER}
  context:
    cluster: ${CLUSTER}
    namespace: ${NAMESPACE}
    user: ${SERVICE_ACCOUNT}
current-context: ${SERVICE_ACCOUNT}@${CLUSTER}
users:
- name: ${SERVICE_ACCOUNT}
  user:
    token: ${TOKEN}
EOF

echo "Kubeconfig generated: kubeconfig-deploy-user.yaml"
```

Run:
```bash
chmod +x scripts/generate-kubeconfig.sh
./scripts/generate-kubeconfig.sh

# Test
kubectl --kubeconfig=kubeconfig-deploy-user.yaml get pods -n production
kubectl --kubeconfig=kubeconfig-deploy-user.yaml get nodes  # Should fail
```

### 6.4 Use ServiceAccount in CI/CD

```bash
# Store in CI/CD secrets (GitLab CI, GitHub Actions, etc.)
cat kubeconfig-deploy-user.yaml | base64 -w 0

# In CI pipeline:
echo $KUBE_CONFIG | base64 -d > kubeconfig
export KUBECONFIG=kubeconfig
kubectl apply -f manifests/
```

---

## 7. Secure Kubeconfig Storage

### 7.1 Restrict Admin Kubeconfig Access

```bash
# On master nodes
sudo chmod 600 /etc/kubernetes/admin.conf
sudo chown root:root /etc/kubernetes/admin.conf

# Ensure ansible-deploy cannot read it
sudo -u ansible-deploy cat /etc/kubernetes/admin.conf  # Should fail
```

### 7.2 Local Kubeconfig Protection

```bash
# On local machine
chmod 600 ~/.kube/config-lab

# Add to .gitignore
echo "*.kubeconfig" >> ~/.gitignore
echo "kubeconfig*" >> ~/.gitignore
echo ".kube/" >> ~/.gitignore
```

### 7.3 Rotate Certificates Regularly

```bash
# On master nodes (every 6-12 months)
sudo kubeadm certs renew all

# Update kubeconfig
sudo cp /etc/kubernetes/admin.conf ~/.kube/config
```

---

## 8. Monitoring and Auditing

### 8.1 Check fail2ban Status

```bash
# On Proxmox/Bastion
sudo fail2ban-client status sshd
sudo fail2ban-client get sshd banip
```

### 8.2 Monitor SSH Attempts

```bash
# On all hosts
sudo tail -f /var/log/auth.log | grep sshd
```

### 8.3 Kubernetes Audit Logs

```bash
# On master nodes
sudo tail -f /var/log/kubernetes/audit.log

# Check for unauthorized access attempts
sudo grep "Forbidden" /var/log/kubernetes/audit.log
```

### 8.4 UFW Status

```bash
# On K8s nodes
sudo ufw status verbose
sudo ufw show added
```

---

## 9. Terraform Integration

### 9.1 Update Terraform to Use Ansible User

Modify your Terraform provisioner:

```hcl
resource "proxmox_vm_qemu" "k8s_node" {
  # ... VM configuration ...

  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for cloud-init to complete...'",
      "cloud-init status --wait"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"  # Initial user
      host        = self.default_ipv4_address
      private_key = file("~/.ssh/id_ed25519")
      
      bastion_host        = "10.0.0.11"
      bastion_user        = "zanzibar"
      bastion_private_key = file("~/.ssh/id_ed25519")
    }
  }

  provisioner "local-exec" {
    command = <<-EOT
      ansible-playbook -i '${self.default_ipv4_address},' \
        -u ubuntu \
        --ssh-common-args='-o ProxyJump=zanzibar@10.0.0.11' \
        playbooks/security-hardening.yml
    EOT
  }
}
```

---

## 10. Automation Script

Create `scripts/setup-security.sh` to automate the entire process:

```bash
#!/bin/bash
set -e

echo "=== Kubernetes Lab Security Setup ==="

# Check prerequisites
command -v ansible-playbook >/dev/null 2>&1 || { echo "Ansible required"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl required"; exit 1; }

# 1. Harden nodes
echo "[1/5] Hardening Kubernetes nodes..."
ansible-playbook -i inventory/hosts.ini playbooks/security-hardening.yml

# 2. Deploy Kubespray
echo "[2/5] Deploying Kubernetes with Kubespray..."
cd kubespray
ansible-playbook -i ../inventory/mycluster/hosts.yaml \
  --become --become-user=root \
  cluster.yml
cd ..

# 3. Retrieve kubeconfig
echo "[3/5] Retrieving kubeconfig..."
ssh bastion "mkdir -p ~/.kube"
ssh bastion "ssh ansible-deploy@10.0.0.100 'sudo cat /etc/kubernetes/admin.conf' > ~/.kube/config"
scp bastion:~/.kube/config ~/.kube/config-lab
chmod 600 ~/.kube/config-lab
export KUBECONFIG=~/.kube/config-lab

# 4. Setup RBAC
echo "[4/5] Configuring RBAC..."
kubectl create namespace production || true
kubectl create serviceaccount deploy-user -n production || true
kubectl apply -f rbac/deploy-role.yaml

# 5. Generate ServiceAccount kubeconfig
echo "[5/5] Generating ServiceAccount kubeconfig..."
./scripts/generate-kubeconfig.sh

echo "=== Setup Complete ==="
echo "Admin kubeconfig: ~/.kube/config-lab"
echo "Deploy kubeconfig: kubeconfig-deploy-user.yaml"
echo ""
echo "Test with:"
echo "  export KUBECONFIG=~/.kube/config-lab"
echo "  kubectl get nodes"
```

---

## 11. Verification Checklist

After setup, verify all security measures:

```bash
# 1. SSH access
ssh proxmox-admin@10.10.10.1  # Via WireGuard
ssh bastion
ssh 10.0.0.100  # Via jumps

# 2. Root access disabled
ssh root@10.10.10.1  # Should fail
ssh root@10.0.0.11  # Should fail

# 3. Password auth disabled
ssh -o PreferredAuthentications=password proxmox-admin@10.10.10.1  # Should fail

# 4. fail2ban active
sudo fail2ban-client status sshd

# 5. UFW configured
sudo ufw status

# 6. Kubernetes access
export KUBECONFIG=~/.kube/config-lab
kubectl get nodes

# 7. RBAC working
kubectl --kubeconfig=kubeconfig-deploy-user.yaml get pods -n production  # Should work
kubectl --kubeconfig=kubeconfig-deploy-user.yaml get nodes  # Should fail

# 8. Admin kubeconfig protected
ssh ansible-deploy@10.0.0.100 "sudo cat /etc/kubernetes/admin.conf"  # Should fail
```

---

## 12. Maintenance Tasks

### Monthly
- Review fail2ban logs and banned IPs
- Check for Kubernetes security updates
- Audit RBAC permissions

### Quarterly
- Rotate WireGuard keys
- Review and update firewall rules
- Test disaster recovery procedures

### Annually
- Renew Kubernetes certificates (`kubeadm certs renew all`)
- Full security audit
- Update all components (Kubespray, Ansible, etc.)

---

## Troubleshooting

### Can't Connect via WireGuard
```bash
# Check WireGuard status
sudo wg show

# Check routing
ip route | grep wg0

# Test connectivity
ping 10.10.10.1

# Check firewall
sudo ufw status
```

### SSH Connection Refused
```bash
# Check if SSH is listening
sudo netstat -tlnp | grep :22

# Check fail2ban
sudo fail2ban-client status sshd
sudo fail2ban-client set sshd unbanip YOUR_IP
```

### Ansible Can't Connect to Nodes
```bash
# Test connection manually
ssh -J zanzibar@10.0.0.11 ansible-deploy@10.0.0.100

# Check UFW on target
ssh 10.0.0.100 "sudo ufw status"

# Verify SSH key
ssh-add -l
```

### Kubectl Permission Denied
```bash
# Check kubeconfig
kubectl config view

# Verify RBAC
kubectl auth can-i get pods --as=system:serviceaccount:production:deploy-user -n production

# Check ServiceAccount token
kubectl get sa deploy-user -n production -o yaml
```

---

## References

- [Kubespray Documentation](https://kubespray.io/)
- [Kubernetes RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [WireGuard Quick Start](https://www.wireguard.com/quickstart/)
- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)

---

**Document Version:** 1.0  
**Last Updated:** 2026-02-06  
**Author:** Denis
