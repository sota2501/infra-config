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

## ZFS NFSサーバーの構築(fox側手動手順)

Proxmoxホスト fox 上にZFSデータセット `zpool/iris-nfs` を作成し、NFSで共有する。
k8sクラスタからネットワーク経由でマウントできる共有ストレージとして利用する。

### 前提

- fox(`192.168.1.97`)にZFSプール `zpool` が存在すること
- fox上でroot権限があること

### fox側の手順

```bash
# 1. NFS サーバーパッケージのインストール
apt install -y nfs-kernel-server

# 2. ZFS データセットの作成
zfs create zpool/iris-nfs

# 3. マウントポイントの確認
#    ZFS が自動的に /zpool/iris-nfs にマウントする
zfs get mountpoint zpool/iris-nfs
# NAME            PROPERTY    VALUE           SOURCE
# zpool/iris-nfs   mountpoint  /zpool/iris-nfs  default

# 4. NFS エクスポートの設定
#    k8s ネットワーク(192.168.1.0/24)からのアクセスのみ許可する。
#    no_root_squash: k8s の NFS プロビジョナーが PV 用サブディレクトリの
#    作成・権限変更を root で行うために必要。
cat >> /etc/exports << 'EOF'
/zpool/iris-nfs 192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)
EOF

# 5. エクスポートの反映
exportfs -ra

# 6. NFS サーバーの起動・自動起動の有効化
systemctl enable --now nfs-kernel-server

# 7. エクスポートの確認
exportfs -v
# /zpool/iris-nfs  192.168.1.0/24(rw,...,no_root_squash,no_subtree_check) が
# 出力されること
```

### k8sノードからの疎通確認

```bash
# k8s VM(iris-k8s-wk-1 等)から実行

# nfs-common は ansible の 01-prereqs.yml(common ロール)で全ノードに導入済み

# エクスポート一覧の確認
showmount -e 192.168.1.97
# Export list for 192.168.1.97:
# /zpool/iris-nfs 192.168.1.0/24

# テストマウント
mkdir -p /mnt/test-nfs
mount -t nfs 192.168.1.97:/zpool/iris-nfs /mnt/test-nfs
df -h /mnt/test-nfs
umount /mnt/test-nfs
rmdir /mnt/test-nfs
```

### k8s側での利用

NFSをk8sのPersistent Volumeとして使う場合は、
[k8s-manifests](https://github.com/sota2501/k8s-manifests)側に
NFS CSIドライバー（[csi-driver-nfs](https://github.com/kubernetes-csi/csi-driver-nfs)）
またはnfs-subdir-external-provisionerをデプロイし、StorageClassから
`192.168.1.97:/zpool/iris-nfs` を参照する。

## 現状

雛形のみ。VMテンプレート作成手順(cloud-init対応、Packer化など)や、実Proxmox環境での
動作確認はこれから。
