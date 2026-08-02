variable "name" {
  type = string
}

variable "node_name" {
  type = string
}

variable "vm_id" {
  type = number
}

variable "clone_template_id" {
  type = number
}

variable "cores" {
  type = number
}

variable "memory" {
  type = number # MiB
}

variable "disk_gb" {
  type = number
}

variable "datastore_id" {
  type = string
}

variable "network_bridge" {
  type = string
}

variable "ip_cidr" {
  type = string
}

variable "gateway" {
  type = string
}

variable "dns_servers" {
  description = "未指定(null)の場合、Proxmox VE ノードの DNS 設定がそのまま使われる"
  type        = list(string)
  default     = null
}

variable "username" {
  type = string
}

variable "ssh_public_keys" {
  type = list(string)
}
