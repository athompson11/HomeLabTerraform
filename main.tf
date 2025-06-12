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

  count = 8
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

  count = 4
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

  count = 5
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

module "queen" {
  source = "./control_nodes/queen"

  providers = {
    proxmox = proxmox
  }
  count = 3
  name            = local.zerg_queens[count.index]
  vm_id           = 9000 + count.index
  node_name       = "vmware"
  network_bridge  = "vmbr1"
  ssh_key         = data.local_file.ssh_public_key.content
  file_id = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
}

module "overmind" { #Jumpbox so doesn't need count or much resources
  source = "./control_nodes/overmind"

  providers = {
    proxmox = proxmox
  }

  name            = "Overmind"
  vm_id           = 500
  node_name       = "vmware"
  network_bridge  = "vmbr1"
  ssh_key         = data.local_file.ssh_public_key.content
  file_id = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
}

module "rancher" {
  source = "./control_nodes/rancher"
  count = 3
  providers = {
    proxmox = proxmox
  }

  name            = local.farmer_names[count.index]
  vm_id           = 6000 + count.index
  node_name       = "vmware"
  network_bridge  = "vmbr1"
  ip_address      = local.farmer_ips[count.index]
  file_id = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
  ssh_key         = data.local_file.ssh_public_key.content
  mac_address = local.farmer_macs[count.index]
}


data "local_file" "ssh_public_key" {
  filename = "./homelab.pub"
}

locals {
  farmer_names = ["Brown", "Green", "Violent"]
  zerg_queens = ["Kerrigan", "Zagara", "Niadra"]
  farmer_ips = ["10.10.10.247/24", "10.10.10.248/24", "10.10.10.249/24"]
  farmer_macs = ["FA:F0:DE:AD:B3:3F", "B0:0B:50:CA:77:00", "AC:AB:AC:AB:AC:AB"]
  zergling_ips = [for vm in module.zergling : tostring(vm.vm_ipv4_address)] # Module calls with count concatenate the objects into a tuple
  hydralisk_ips = [for vm in module.hydralisk : tostring(vm.vm_ipv4_address)]
  swarmhost_ips = [for vm in module.swarmhost : tostring(vm.vm_ipv4_address)]
  ultralisk_ips = [for vm in module.ultralisk : tostring(vm.vm_ipv4_address)]
  queen_ips = [for vm in module.queen : tostring(vm.vm_ipv4_address)]
  farmer_inventory_ips = [for vm in module.rancher : tostring(vm.vm_ipv4_address)]
}

resource "local_file" "ansible_inventory" {
  filename = "./ansible_inventory.ini"

  content  = <<-EOT
      [zerglings]
      ${join("\n",local.zergling_ips)}
      [hydralisks]
      ${join("\n",local.hydralisk_ips)}
      [swarmhosts]
      ${join("\n",local.swarmhost_ips)}
      [ultralisks]
      ${join("\n",local.ultralisk_ips)}
      [queens]
      ${join("\n",local.queen_ips)}
      [overmind]
      ${module.overmind.vm_ipv4_address[0]}
      [farmers]
      ${join("\n",local.farmer_inventory_ips)}
      [internal:children]
      zerglings
      hydralisks
      swarmhosts
      ultralisks
      queens
      farmers
      [internal:vars]
      ansible_ssh_common_args='-o ProxyJump=overmind@{{ groups["overmind"][0] }}'  
EOT

  depends_on = [ 
    module.zergling,
    module.hydralisk,
    module.swarmhost,
    module.ultralisk,
    module.queen,
    module.overmind
  ]
}
