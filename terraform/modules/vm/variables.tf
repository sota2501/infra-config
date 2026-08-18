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

variable "data_disk_gb" {
  description = "追加データディスク(scsi1)のサイズ(GB)。nullなら追加しない。OSディスク(scsi0)とは独立させることで、cloud-initのgrowpartによる自動拡張の影響を受けない領域を確保する(ZFS等の用途向け)。"
  type        = number
  default     = null
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
