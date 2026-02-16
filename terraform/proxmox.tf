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
    type  = "host" # Required for GPU passthrough
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
  machine       = "q35" # Required for PCI passthrough
  scsi_hardware = "virtio-scsi-single"

  # GPU Passthrough - NVIDIA RTX 3060
  # Device ID from: lspci -nn | grep -i nvidia on gondor
  # 01:00.0 = GPU, 01:00.1 = Audio (both passed as single device)
  hostpci {
    device = "hostpci0"
    id     = "0000:01:00"
    pcie   = true
    rombar = true
  }

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
      hostpci, # GPU passthrough configured via qm (API token lacks permission)
      machine,
      cpu,
    ]
  }
}

# =============================================================================
# The Shire VMs
# =============================================================================

# =============================================================================
# Frodo - Home Assistant OS VM
# =============================================================================
# HAOS is created and managed manually in Proxmox UI since:
# - QCOW2 disk import is not supported via Terraform
# - HAOS has its own update mechanism
#
# Manual setup:
# 1. wget https://github.com/home-assistant/operating-system/releases/download/<version>/haos_ova-<version>.qcow2.xz
# 2. xz -d haos_ova-<version>.qcow2.xz
# 3. qm create 102 --name frodo --memory 4096 --cores 2 --net0 virtio,bridge=vmbr0,macaddr=02:33:3E:B2:81:19
# 4. qm importdisk 102 haos_ova-<version>.qcow2 local-lvm
# 5. qm set 102 --scsi0 local-lvm:vm-102-disk-1 --boot order=scsi0 --bios ovmf --machine q35
# 6. qm set 102 --efidisk0 local-lvm:1,format=raw,efitype=4m
# 7. qm start 102
#
# VM ID: 102, IP: 192.168.1.25 (DHCP reservation in opnsense.tf)

# =============================================================================
# Samwise - NixOS VM with Zigbee2MQTT
# =============================================================================
# Hosts zigbee2mqtt and Mosquitto MQTT broker.
#
# USB Passthrough (must be done manually via CLI, API tokens can't set USB):
#   ssh root@the-shire
#   lsusb | grep -i silicon  # Find vendor:product ID
#   qm set 103 -usb0 host=10c4:ea60  # SONOFF ZBDongle-P
#   # Or for ZBDongle-E: qm set 103 -usb0 host=1a86:55d4

resource "proxmox_virtual_environment_vm" "samwise" {
  name      = "samwise"
  node_name = "the-shire"
  vm_id     = 103

  on_boot = true
  started = true

  cpu {
    cores = 4
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 8192
  }

  boot_order = ["scsi0", "ide2", "net0"]

  # Root disk
  disk {
    datastore_id = var.proxmox_datastore
    size         = 64
    interface    = "scsi0"
    file_format  = "raw"
    iothread     = true
  }

  network_device {
    bridge      = "vmbr0"
    mac_address = local.mac_addresses.samwise
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
      disk,
      boot_order,
      cdrom,
      usb, # USB passthrough managed via CLI (requires root)
    ]
  }
}

# =============================================================================
# Rohan VMs
# =============================================================================

# =============================================================================
# Theoden - NixOS VM for k3s cluster + NFS storage
# =============================================================================
# Part of the k3s HA cluster (server node). Also serves as NFS storage server
# with passthrough disks (migrated from faramir). Only VM on Rohan.

resource "proxmox_virtual_environment_vm" "theoden" {
  name      = "theoden"
  node_name = "rohan"
  vm_id     = 104

  on_boot = true
  started = true

  cpu {
    cores = 4 # All cores on rohan (i5-3570K, cleaned & repasted)
    type  = "host"
  }

  memory {
    dedicated = 22528 # 22GB, leaving ~2GB for Proxmox host
  }

  boot_order = ["scsi0", "ide2", "net0"]

  # Root disk
  disk {
    datastore_id = var.proxmox_datastore
    size         = 100
    interface    = "scsi0"
    file_format  = "raw"
    iothread     = true
  }

  network_device {
    bridge      = "vmbr0"
    mac_address = local.mac_addresses.theoden
  }

  agent {
    enabled = true
  }

  bios          = "seabios"
  scsi_hardware = "virtio-scsi-single"

  # NOTE: GPU passthrough not possible - rohan's motherboard (ASRock Z77 Extreme4)
  # does not support VT-d. The 1070 Ti cannot be passed through to this VM.

  operating_system {
    type = "l26"
  }

  serial_device {}

  lifecycle {
    ignore_changes = [
      disk,
      boot_order,
      cdrom,
    ]
  }
}

# =============================================================================
# Pippin - Clawdbot AI Assistant VM
# =============================================================================
# Isolated VM for clawdbot to safely execute arbitrary commands.

resource "proxmox_virtual_environment_vm" "pippin" {
  name      = "pippin"
  node_name = "the-shire"
  vm_id     = 105

  on_boot = true
  started = true

  cpu {
    cores = 1
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 2048 # 2GB for clawdbot + tools
  }

  boot_order = ["scsi0", "ide2", "net0"]

  disk {
    datastore_id = var.proxmox_datastore
    size         = 48
    interface    = "scsi0"
    file_format  = "raw"
    iothread     = true
  }

  network_device {
    bridge      = "vmbr0"
    mac_address = local.mac_addresses.pippin
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
      disk,
      boot_order,
      cdrom,
    ]
  }
}
