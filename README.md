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

## 既知の制限: VSCode拡張機能のAnsible警告は誤検知することがある

`ansible.cfg`は(terraformと同様)`ansible/`配下にあり、CLIは`ansible/`に`cd`して実行する前提
(このリポジトリの構成そのもの)。VSCodeのAnsible拡張機能(非コンテナ/Execution Environment
モード時)はリポジトリルートを作業ディレクトリにして`ansible-lint`を実行するため、
`ansible.cfg`の`roles_path`を読めず`the role 'xxx' was not found`のような誤検知が
Problemsパネルに出ることがある。これを直接解決する拡張機能側の設定項目は無い
(調査済み: `Execution Environment`関連の設定はコンテナ実行用で今回の件とは無関係、
CLI引数だけで`roles_path`を上書きする手段もansible-core自体に存在しない)。

**実際の正しさはCLIで判断すること**:
```sh
cd ansible && ansible-lint   # production profile 全通過が正
```
Problemsパネルの`role not found`等はこの既知の制限による誤検知の可能性が高い。

## 現状

雛形のみ。VMテンプレート作成手順(cloud-init対応、Packer化など)や、実Proxmox環境での
動作確認はこれから。
