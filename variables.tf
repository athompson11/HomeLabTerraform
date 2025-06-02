variable "terraform_pam_password" {
  description = "Password for the Proxmox VE user"
  type        = string
  sensitive   = true
}

variable "terraform_root_password" {
  description = "Password for the Proxmox VE root user"
  type        = string
  sensitive   = true
}

variable "proxmox_api_token" {
  description = "API token for Proxmox VE in the format 'user@realm!tokenid=tokenprivatekey'"
  type        = string
  sensitive   = true
}