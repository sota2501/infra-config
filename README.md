# infra-config

自宅サーバ(homelab)向け Kubernetes クラスタを Proxmox 上に構築するための
Infrastructure as Code(Terraform / Ansible)一式。

GitOpsで同期されるKubernetesマニフェスト本体は
[k8s-manifests](https://github.com/sota2501/k8s-manifests)に分離している
(ArgoCDが継続的に参照・同期するのはそちらのみ。このリポジトリはVMプロビジョニングと
クラスタの初期ブートストラップまでを担当する)。

## 全体の流れ

1. **`terraform/`** — Proxmox API 経由で control-plane / worker VM を作成する
2. **`ansible/`** — 作成した VM に OS 設定・containerd・kubeadm クラスタ・CNI をセットアップし、
   最後に ArgoCD をインストールして [k8s-manifests](https://github.com/sota2501/k8s-manifests) の
   `apps/root-app.yaml` を apply する(以降はGitOpsに引き継がれ、このリポジトリでの作業は不要になる)

```
terraform/   Proxmox VM プロビジョニング(control-plane / worker)
ansible/      OSセットアップ・kubeadmクラスタ構築・ArgoCD bootstrap
```

## 使い方(想定)

```sh
cd terraform
cp secret.auto.tfvars.example secret.auto.tfvars
# secret.auto.tfvars に Proxmox 接続情報(秘密情報)を記載
# terraform.tfvars(クラスタ構成)は Git 管理下にあるので必要に応じて編集
terraform init && terraform apply

cd ../ansible
# inventory/home/hosts.yml の ansible_host を terraform output の実IPに更新
ansible-galaxy collection install -r requirements.yml

# k8s-manifests は private リポジトリのため、読み取り用 GitHub PAT を
# group_vars/all/vault.yml に設定して ansible-vault で暗号化しておく
# (詳細は group_vars/all/vault.yml のコメント参照)。
ansible-vault encrypt inventory/home/group_vars/all/vault.yml

ansible-playbook playbooks/site.yml --ask-vault-pass
```

## 現状

雛形のみ。VMテンプレート作成手順(cloud-init対応、Packer化など)や、実Proxmox環境での
動作確認はこれから。
