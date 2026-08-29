# クラスタのトポロジー(非秘密情報)。Git 管理下に置く。
# 秘密情報(Proxmox接続情報)は secret.auto.tfvars に分離している。
# secret.auto.tfvars.example をコピーして各自の環境に合わせて作成すること。

vm_template_id    = 9000 # 事前に用意した cloud-init 対応テンプレートの VM ID
vm_datastore_id   = "local-lvm"
vm_network_bridge = "vmbr0"

# ssh_public_key は明示指定しなければ github_username の公開鍵
# (https://github.com/<user>.keys) を自動取得する。両方指定した場合は ssh_public_key が優先。
# ssh_public_key = "ssh-ed25519 AAAA... user@example.com"
github_username = "sota2501"

network_gateway = "192.168.1.1"

control_plane_nodes = {
  "iris-k8s-cp-1" = {
    vm_id     = 1001
    cores     = 2
    memory    = 2048
    disk_gb   = 30
    ip_cidr   = "192.168.1.129/24"
    node_name = "fox"
  }
}

worker_nodes = {
  "iris-k8s-wk-1" = {
    vm_id        = 1101
    cores        = 2
    memory       = 8192
    disk_gb      = 30
    data_disk_gb = 50
    ip_cidr      = "192.168.1.144/24"
    node_name    = "fox"
  }
}
