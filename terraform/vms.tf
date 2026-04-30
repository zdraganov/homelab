locals {
  vms = {
    truenas = {
      vmid          = 100
      name          = "truenas"
      cores         = 2
      memory        = 8192
      disk          = 32
      onboot        = true
      cpu_type      = "x86-64-v2-AES"
      scsi_hardware = "virtio-scsi-single"
      firewall      = true
    }
    dev-vm = {
      vmid          = 110
      name          = "dev-vm"
      cores         = 4
      memory        = 4096
      disk          = 30
      onboot        = false
      cpu_type      = "qemu64"
      scsi_hardware = "virtio-scsi-pci"
      firewall      = false
    }
  }
}

resource "proxmox_virtual_environment_vm" "vm" {
  for_each = local.vms

  node_name = "pve"
  vm_id     = each.value.vmid
  name      = each.value.name

  cpu {
    cores = each.value.cores
    type  = each.value.cpu_type
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = each.value.disk
  }

  scsi_hardware = each.value.scsi_hardware

  network_device {
    bridge   = "vmbr0"
    firewall = each.value.firewall
  }

  started = each.value.onboot
  on_boot = each.value.onboot

  lifecycle {
    ignore_changes = [
      disk,
      operating_system,
      serial_device,
      startup,
      cdrom,
    ]
  }
}
