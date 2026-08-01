# terraform

Proxmox VE 上に k8s クラスタ用の VM(control-plane / worker)を作成する。

## 前提

- Proxmox VE が稼働済みで、API トークンを発行済みであること
- cloud-init 対応の VM テンプレートを事前に作成済みであること(例: Ubuntu 22.04/24.04 cloud image を
  `qm create` + `qm template` で テンプレート化。Packer での自動化は今後の課題)
- [bpg/proxmox provider](https://registry.terraform.io/providers/bpg/proxmox/latest/docs) を使用

## 使い方(想定)

```sh
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars を実環境に合わせて編集

terraform init
terraform plan
terraform apply
```

`terraform output -json` で得られる IP アドレスを Ansible の inventory (`../ansible/inventory/home/hosts.yml`)
に反映してから Ansible フェーズに進む。TODO: 反映を自動化するスクリプトを用意する。

## 構成

```
main.tf               provider 設定
variables.tf           入力変数(接続情報・ノード定義)
vms.tf                 control-plane / worker VM の定義(modules/vm を for_each で呼び出す)
outputs.tf             生成された VM の IP アドレス一覧
modules/vm/             VM 1台分の共通 clone/cloud-init ロジック
terraform.tfvars.example  変数のサンプル(実値は terraform.tfvars に。Git 管理外)
```

## 現状

雛形のみ。実際の VM テンプレート作成手順や tfvars の値はこれから環境に合わせて詰める。
