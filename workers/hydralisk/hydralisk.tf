terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

variable "name" {
  description = "Name of the VM, note that this is presumed to be provided by the caller as unique"
  type        = string
  default     = "hydralisk"
}

variable "vm_id" {
  description = "ID of the VM"
  type        = number
  default     = 2000
}

variable "node_name" {
  description = "Name of the Proxmox node to deploy the VM on"
  type        = string
  default     = "pve"
}

variable "network_bridge" {
  description = "Internal network bridge to connect the VM to"
  type        = string
  default     = "vmbr1"
}

variable "ssh_key" {
  description = "SSH public key to be used for the VM"
  type        = string
}

variable "file_id" {
  description = "ID of the file to use for the VM disk"
  type        = string  
}

resource "proxmox_virtual_environment_file" "user_data_cloud_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.node_name

  source_raw {
    data = <<-EOF
    #cloud-config
    hostname: ${join("-", [var.name,tostring(var.vm_id)])}
    timezone: America/Chicago
    users:
      - default
      - name: overmind
        groups:
          - sudo
        shell: /bin/bash
        ssh_authorized_keys:
          - ${trimspace(var.ssh_key)}
        sudo: ALL=(ALL) NOPASSWD:ALL
    package_update: true
    packages:
      - qemu-guest-agent
      - net-tools
      - curl
    runcmd:
      - systemctl enable qemu-guest-agent
      - systemctl start qemu-guest-agent
      - echo "done" > /tmp/cloud-config.done
    EOF

    file_name = join("",[join("-", [var.name,"user-data-cloud-config", tostring(var.vm_id)]),".yaml"])
  }
}

resource "proxmox_virtual_environment_vm" "ubuntu_vm" {
  name      = var.name
  node_name = var.node_name
  vm_id = var.vm_id
  description = "Hydralisk (CPU optimized Worker swarm)"
  tags = ["hydralisk","zerg"]
  agent {
    enabled = true
  }

  cpu {
    cores = 6
    sockets = 2
  }

  memory {
    dedicated = 8192 # Size in MB
    floating  = 8192
  }

  disk {
    datastore_id = "local-lvm"
    file_id      = var.file_id
    interface    = "virtio0"
    iothread     = false
    size         = 50 # Size in GB
  }

  initialization {
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.user_data_cloud_config.id
  }

  network_device {
    bridge = var.network_bridge
  }

}

output "vm_ipv4_address" {
  value = proxmox_virtual_environment_vm.ubuntu_vm.ipv4_addresses[1][0]
}