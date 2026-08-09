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

# terraform output (control_plane_ips / worker_ips) を見て、
# inventory/home/hosts.yml の ansible_host を実IPに手動で更新する
# (自動反映の仕組みはまだ無い。terraform/outputs.tf の TODO 参照)

# requirements.yml に列挙された Galaxy コレクション(IPとは無関係)をインストール
ansible-galaxy collection install -r requirements.yml

# k8s-manifests は private リポジトリのため、読み取り用 GitHub PAT を
# group_vars/all/secrets.yml (git 管理外) に設定する
cp inventory/home/group_vars/all/secrets.yml.example inventory/home/group_vars/all/secrets.yml
# secrets.yml の gitops_repo_token を実際の PAT に書き換える

ansible-playbook playbooks/site.yml
```

## VSCode で開く場合

`ansible.cfg`は(terraformと同様)`ansible/`配下にあり、CLIは`ansible/`に`cd`して実行する前提。
VSCodeのAnsible拡張機能はワークスペースフォルダを作業ディレクトリにしてansible-lintを実行するため、
リポジトリルートをそのままフォルダとして開くと`ansible.cfg`を見つけられず誤検知が出る。
`infra-config.code-workspace`をワークスペースとして開けば`ansible/`が独立フォルダとして
登録され、正しく検出される(リポジトリ構成自体はCLIの都合を優先し、変更していない)。

## 現状

雛形のみ。VMテンプレート作成手順(cloud-init対応、Packer化など)や、実Proxmox環境での
動作確認はこれから。
