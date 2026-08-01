terraform {
  required_version = ">= 1.7.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }

  # TODO: リモートバックエンド(例: S3/MinIO, Terraform Cloud)を使う場合はここに backend ブロックを追加。
  # 単一ホストで運用する間はローカル state のままでも良いが、tfstate は Git 管理しないこと(.gitignore 参照)。
}
