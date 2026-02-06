# Proxmox Configuration

## Creating the Proxmox user and role for terraform

To ensure security, it's best practice to create a dedicated user and role for Terraform instead of using cluster-wide Administrator rights. The particular privileges required may change but here is a suitable starting point.

Log into the Proxmox host using ssh then:

- Create a new role for the future terraform user.
- Create the user "terraform@pve"
- Add the TerraformRole role to the terraform user

```bash
pveum role add TerraformRole -privs "Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate Pool.Audit Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.PowerMgmt SDN.Use"

pveum user add terraform@pve --password <PASSWORD>

pveum aclmod / -user terraform@pve -role TerraformRole
```

Then we generate a token for the user

```bash
pveum user token add terraform@pve terraform-token
pveum acl modify / -role TerraformRole -token 'terraform@pve!terraform-token'
```

If everything goes well, you should see the generated token in the output of the previous command. You will need to copy it and store it in a safe place, as it will never be displayed again in plain text.

┌──────────────┬──────────────────────────────────────┐
│ key          │ value                                │
╞══════════════╪══════════════════════════════════════╡
│ full-tokenid │ terraform@pve!terraform-token        │
├──────────────┼──────────────────────────────────────┤
│ info         │ {"privsep":"1"}                      │
├──────────────┼──────────────────────────────────────┤
│ value        │ xxxxxx-xxx-xxx-xxx-xxx-xxx-xxx-xxx   │
└──────────────┴──────────────────────────────────────┘

To verify that everything is working correctly, you can use the following command:

```bash
curl -k -H 'Authorization: PVEAPIToken=terraform@pve!terraform-token=${TOKEN}' https://IP:8006/api2/json/nodes
```

## Cloud Init Preparation

To create a VM with Cloud Init, you can use the following command:

```bash
# 1. Download Ubuntu 24.04 cloud image
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img

# 2. Create an empty vm (ID 9999 for instance)
qm create 9999 --name "ubuntu-2404-cloudinit-template" --memory 2048 --net0 virtio,bridge=vmbr1

# 3. Import the downloaded disk image into the VM
qm importdisk 9999 noble-server-cloudimg-amd64.img local-zfs

# 4. Attach the disk to the VM (scsi0)
qm set 9999 --scsihw virtio-scsi-single --scsi0 local-zfs:vm-9999-disk-0

# 5. Add the Cloud-Init reader (This is CRUCIAL, this is where Terraform will write the config)
qm set 9999 --ide2 local-zfs:cloudinit

# 6. Make the disk bootable and configure the serial console (necessary for some cloud-init logs)
qm set 9999 --boot c --bootdisk scsi0
qm set 9999 --serial0 socket --vga serial0

# 7. Create a user with sudo privileges
qm set 9999 --ciuser "zanzibar" --cipassword "p@ssw0rd24445" --sshkeys ~/.ssh/id_ed25519.pub

# 8. Convert the VM into a Template
qm template 9999
```

## CT Template Preparation

To be able to provision a CT with Terraform, you need to get a CT template from proxmox.

```bash
pveam update

pveam available

pveam download local ubuntu-24.04-standard_24.04-2_amd64.tar.zst
```

The downloaded image is stored at `/var/lib/vz/template/cache/ubuntu-24.04-standard_24.04-2_amd64.tar.zst`