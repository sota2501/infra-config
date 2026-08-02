# --- Proxmox 接続情報 ---
# TODO: 実際の値は terraform.tfvars (Git 管理外) に記載する。terraform.tfvars.example を参照。

variable "proxmox_endpoint" {
  description = "Proxmox VE API endpoint (例: https://proxmox.local:8006/)"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token (形式: USER@REALM!TOKENID=UUID)"
  type        = string
  sensitive   = true
}

variable "proxmox_tls_insecure" {
  description = "自己署名証明書を使っている場合は true"
  type        = bool
  default     = false
}

variable "proxmox_ssh_username" {
  description = "Terraform が cloud-init 等のためにホストへ SSH する際のユーザー名(root@pam 等)"
  type        = string
  default     = "root"
}

# --- VM テンプレート ---

variable "vm_template_id" {
  description = "clone 元となる cloud-init 対応テンプレート VM の ID (packer 等で事前作成しておく)"
  type        = number
}

variable "vm_datastore_id" {
  description = "VM ディスク/cloud-init を配置するデータストア名"
  type        = string
  default     = "local-lvm"
}

variable "vm_network_bridge" {
  description = "VM が接続する Linux bridge 名"
  type        = string
  default     = "vmbr0"
}

variable "ssh_public_key" {
  description = "cloud-init で各 VM に登録する公開鍵を明示指定する場合に使う。未指定(null)なら github_username から取得する"
  type        = string
  default     = null
}

variable "vm_username" {
  description = "cloud-init で各 VM に作成するユーザー名"
  type        = string
  default     = "cloudinit"
}

variable "github_username" {
  description = "ssh_public_key が未指定の場合に、公開鍵の取得元として使う GitHub ユーザー名(https://github.com/<user>.keys から全公開鍵を取得する)"
  type        = string
  default     = null
}

# --- クラスタノード定義 ---
# control_plane / workers それぞれの台数・スペック・固定IPをここで宣言する。
# TODO: 台数・スペック・IPレンジは実環境に合わせて terraform.tfvars で上書きする。

variable "control_plane_nodes" {
  description = "control-plane ノードの定義。node_name には VM を配置する Proxmox ノード名を明示的に指定する"
  type = map(object({
    vm_id     = number
    cores     = number
    memory    = number # MiB
    disk_gb   = number
    ip_cidr   = string # 例: 192.168.1.11/24
    node_name = string
  }))
}

variable "worker_nodes" {
  description = "worker ノードの定義。node_name には VM を配置する Proxmox ノード名を明示的に指定する"
  type = map(object({
    vm_id     = number
    cores     = number
    memory    = number # MiB
    disk_gb   = number
    ip_cidr   = string
    node_name = string
  }))
}

variable "network_gateway" {
  description = "VM に設定するデフォルトゲートウェイ"
  type        = string
}

variable "network_dns_servers" {
  description = "VM に設定する DNS サーバー。未指定(null)の場合、Proxmox VE ノードの DNS 設定がそのまま使われる"
  type        = list(string)
  default     = null
}
