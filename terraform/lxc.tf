locals {
  lxc_containers = {
    plex = {
      vmid         = 101
      hostname     = "plex"
      cores        = 2
      memory       = 2048
      disk         = 8
      template     = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
      onboot       = true
      unprivileged = true
      features     = { nesting = true, keyctl = true }
      firewall     = false
      mounts = [
        { volume = "/mnt/pve/Movies", path = "/mnt/Movies" },
        { volume = "/mnt/pve/TV", path = "/mnt/TV" },
      ]
      gpu_passthrough = []
    }
    cloudflared = {
      vmid         = 102
      hostname     = "cloudflared"
      cores        = 1
      memory       = 512
      disk         = 2
      template     = "local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
      onboot       = true
      unprivileged = true
      features     = { nesting = true, keyctl = true }
      firewall     = false
      mounts       = []
      gpu_passthrough = []
    }
    netbird = {
      vmid         = 103
      hostname     = "netbird"
      cores        = 1
      memory       = 1024
      disk         = 8
      template     = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
      onboot       = false
      unprivileged = true
      features     = { nesting = true, keyctl = false }
      firewall     = true
      mounts       = []
      gpu_passthrough = []
    }
    dockge = {
      vmid         = 104
      hostname     = "dockge"
      cores        = 2
      memory       = 4096
      disk         = 20
      template     = "local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
      onboot       = true
      unprivileged = false
      features     = { nesting = true, keyctl = true }
      firewall     = false
      mounts       = []
      gpu_passthrough = []
    }
    transmission = {
      vmid         = 105
      hostname     = "transmission"
      cores        = 2
      memory       = 2048
      disk         = 8
      template     = "local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
      onboot       = true
      unprivileged = false
      features     = { nesting = true, keyctl = false }
      firewall     = false
      mounts = [
        { volume = "/mnt/pve/Movies", path = "/Downloads/Movies" },
        { volume = "/mnt/pve/TV", path = "/Downloads/TV" },
      ]
      gpu_passthrough = []
    }
    immich = {
      vmid         = 106
      hostname     = "immich"
      cores        = 4
      memory       = 8192
      disk         = 20
      template     = "local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
      onboot       = true
      unprivileged = false
      features     = { nesting = true, keyctl = false }
      firewall     = false
      mounts = [
        { volume = "/mnt/pve/Photos", path = "/mnt/Photos" },
      ]
      gpu_passthrough = [
        { path = "/dev/dri/renderD128", gid = 992 },
        { path = "/dev/dri/renderD129", gid = 992 },
        { path = "/dev/dri/card0", gid = 44 },
        { path = "/dev/dri/card1", gid = 44 },
      ]
    }
  }
}

resource "proxmox_virtual_environment_container" "lxc" {
  for_each = local.lxc_containers

  node_name = "pve"
  vm_id     = each.value.vmid

  initialization {
    hostname = each.value.hostname
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  cpu {
    cores = each.value.cores
  }

  memory {
    dedicated = each.value.memory
    swap      = 512
  }

  disk {
    datastore_id = "local-lvm"
    size         = each.value.disk
  }

  dynamic "mount_point" {
    for_each = each.value.mounts
    content {
      volume = mount_point.value.volume
      path   = mount_point.value.path
    }
  }

  dynamic "device_passthrough" {
    for_each = each.value.gpu_passthrough
    content {
      path = device_passthrough.value.path
      gid  = device_passthrough.value.gid
    }
  }

  network_interface {
    name     = "eth0"
    bridge   = "vmbr0"
    firewall = each.value.firewall
  }

  operating_system {
    template_file_id = each.value.template
  }

  features {
    nesting = lookup(each.value.features, "nesting", false)
    keyctl  = lookup(each.value.features, "keyctl", false)
  }

  started       = true
  start_on_boot = each.value.onboot
  unprivileged  = each.value.unprivileged

  lifecycle {
    ignore_changes = [
      operating_system,
      initialization,
      console,
      startup,
      description,
      tags,
      features,
    ]
  }
}
