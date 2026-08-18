# cloud-init 対応テンプレートを clone して k8s ノード用 VM を作成する共通モジュール。
# k8s のワークロード要件(スワップ無効化, br_netfilter 等)は Ansible 側で設定する。

resource "proxmox_virtual_environment_vm" "this" {
  name      = var.name
  node_name = var.node_name
  vm_id     = var.vm_id

  clone {
    vm_id = var.clone_template_id
    full  = true
  }

  agent {
    enabled = true
  }

  cpu {
    cores = var.cores
    type  = "host"
  }

  memory {
    dedicated = var.memory
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = var.disk_gb
  }

  dynamic "disk" {
    for_each = var.data_disk_gb == null ? [] : [var.data_disk_gb]
    content {
      datastore_id = var.datastore_id
      interface    = "scsi1"
      size         = disk.value
    }
  }

  network_device {
    bridge = var.network_bridge
  }

  initialization {
    ip_config {
      ipv4 {
        address = var.ip_cidr
        gateway = var.gateway
      }
    }

    dynamic "dns" {
      for_each = var.dns_servers == null ? [] : [var.dns_servers]
      content {
        servers = dns.value
      }
    }

    user_account {
      username = var.username
      keys     = var.ssh_public_keys
    }
  }

  operating_system {
    type = "l26"
  }
}
