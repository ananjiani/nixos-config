# Proxmox Virtual Environment Configuration
#
# Manages VMs on the Proxmox cluster. VMs are defined here but NixOS
# configuration is managed separately in the hosts/ directory.
#
# Prerequisites:
# 1. Create API token in Proxmox UI (Datacenter → Permissions → API Tokens)
# 2. Add token to secrets/secrets.yaml as proxmox_api_token
# 3. For faramir: Get disk IDs with `ls -la /dev/disk/by-id/` on Proxmox host

# =============================================================================
# Boromir - Main NixOS VM
# =============================================================================
# Minimal VM for general services. Imported from existing manually-created VM.
# Import with: terraform import proxmox_virtual_environment_vm.boromir gondor/qemu/<vmid>

resource "proxmox_virtual_environment_vm" "boromir" {
  name      = "boromir"
  node_name = var.proxmox_node
  vm_id     = 100

  on_boot = true
  started = true

  cpu {
    cores = 4
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 28672
  }

  boot_order = ["scsi0", "ide2", "net0"]

  # Root disk
  disk {
    datastore_id = var.proxmox_datastore
    size         = 200
    interface    = "scsi0"
    file_format  = "raw"
    iothread     = true
  }

  # Network
  network_device {
    bridge      = "vmbr0"
    mac_address = local.mac_addresses.boromir
  }

  agent {
    enabled = true
  }

  bios          = "seabios"
  scsi_hardware = "virtio-scsi-single"

  operating_system {
    type = "l26"
  }

  serial_device {}

  lifecycle {
    ignore_changes = [
      # Ignore changes managed outside Terraform
      disk,
      boot_order,
      cdrom,
    ]
  }
}

# =============================================================================
# Faramir - NFS Server VM
# =============================================================================
# NFS server with passthrough disks for storage. Created manually in Proxmox UI
# because API tokens cannot pass arbitrary filesystem paths for disk passthrough.
# Import with: tofu import proxmox_virtual_environment_vm.faramir 'gondor:qemu/101'

resource "proxmox_virtual_environment_vm" "faramir" {
  name      = "faramir"
  node_name = var.proxmox_node
  vm_id     = 101

  on_boot = true
  started = true

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 2048
  }

  boot_order = ["scsi0"]

  # Root disk
  disk {
    datastore_id = var.proxmox_datastore
    size         = 32
    interface    = "scsi0"
    file_format  = "raw"
  }

  # Network
  network_device {
    bridge      = "vmbr0"
    mac_address = local.mac_addresses.faramir
  }

  bios          = "seabios"
  scsi_hardware = "virtio-scsi-single"

  operating_system {
    type = "l26"
  }

  serial_device {}

  lifecycle {
    ignore_changes = [
      # Ignore disk changes - passthrough disks managed outside Terraform
      disk,
      boot_order,
      cdrom,
    ]
  }
}
