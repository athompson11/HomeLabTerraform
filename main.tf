terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}


provider "proxmox" {
  endpoint = "https://192.168.1.83:8006"

  api_token = var.proxmox_api_token

  # because self-signed TLS certificate is in use
  insecure = true

  ssh {
    node{
      name = "vmware"
      address = "192.168.1.83"
    }
    agent = true
    username = "terraform"
  }
}

resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = "vmware"

  url = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

module "zergling" {
  source = "./workers/zergling"

  providers = {
    proxmox = proxmox
  }

  count = 10
  name            = join("-", ["zergling", count.index + 1])
  vm_id           = 1000 + count.index
  node_name       = "vmware"
  network_bridge  = "vmbr1"
  ssh_key         = data.local_file.ssh_public_key.content
  file_id = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
}

module "hydralisk" {
  source = "./workers/hydralisk"

  providers = {
    proxmox = proxmox
  }

  count = 5
  name            = join("-", ["hydralisk", count.index + 1])
  vm_id           = 2000 + count.index
  node_name       = "vmware"
  network_bridge  = "vmbr1"
  ssh_key         = data.local_file.ssh_public_key.content
  file_id = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
}

module "swarmhost" {
  source = "./workers/swarmhost"

  providers = {
    proxmox = proxmox
  }

  count = 4
  name            = join("-", ["swarmhost", count.index + 1])
  vm_id           = 3000 + count.index
  node_name       = "vmware"
  network_bridge  = "vmbr1"
  ssh_key         = data.local_file.ssh_public_key.content
  file_id = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
}

module "ultralisk" {
  source = "./workers/ultralisk"

  providers = {
    proxmox = proxmox
  }

  count = 3
  name            = join("-", ["ultralisk", count.index + 1])
  vm_id           = 4000 + count.index
  node_name       = "vmware"
  network_bridge  = "vmbr1"
  ssh_key         = data.local_file.ssh_public_key.content
  file_id = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
}


data "local_file" "ssh_public_key" {
  filename = "./homelab.pub"
}

locals {
  zergling_ips = [for vm in module.zergling : tostring(vm.vm_ipv4_address)] # Module calls with count concatenate the objects into a tuple
  hydralisk_ips = [for vm in module.hydralisk : tostring(vm.vm_ipv4_address)]
  swarmhost_ips = [for vm in module.swarmhost : tostring(vm.vm_ipv4_address)]
  ultralisk_ips = [for vm in module.ultralisk : tostring(vm.vm_ipv4_address)]
}

resource "local_file" "ansible_inventory" {
  filename = "./ansible_inventory.yml"

  content  = <<-EOT
      [zerglings]
      ${join("\n",local.zergling_ips)}
      [hydralisks]
      ${join("\n",local.hydralisk_ips)}
      [swarmhosts]
      ${join("\n",local.swarmhost_ips)}
      [ultralisks]
      ${join("\n",local.ultralisk_ips)}
  EOT

  depends_on = [ 
    module.zergling,
    module.hydralisk,
    module.swarmhost,
    module.ultralisk
  ]
}