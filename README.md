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

## iSCSIターゲットの構築(fox側手動手順)

Proxmoxホスト fox 上にiSCSIターゲット(LIO/targetcli)を構築し、
[Democratic-CSI](https://github.com/democratic-csi/democratic-csi)経由で
k8sクラスタにブロックストレージ(ZFS zvol + iSCSI + ext4)を提供する。

将来的にはLonghornへ移行予定。

### 前提

- fox(`192.168.1.97`)にZFSプール `zpool` が存在すること
- fox上でroot権限があること
- `02-zfs-vm-storage.yml`実行済み(SSH鍵ペアが生成済みであること)

### fox側の手順

```bash
# 1. targetcli のインストール
apt install -y targetcli-fb

# 2. iSCSIターゲットサービスの有効化
systemctl enable --now rtslib-fb-targetctl

# 3. Democratic-CSI用のZFSデータセットを作成
#    zvol(ブロックボリューム)の親となるデータセット。
#    Democratic-CSIが PVC 作成時にこの配下に zvol を自動作成する。
zfs create zpool/iris-iscsi
zfs create zpool/iris-iscsi-snaps

# 4. Democratic-CSI用の専用ユーザーを作成
useradd -m -s /bin/bash csi

# 5. sudoers 設定(zfs / targetcli コマンドをパスワードなしで許可)
#    Democratic-CSIはSSH経由でこれらのコマンドを実行してzvol作成・
#    iSCSIターゲット管理を行う。
cat > /etc/sudoers.d/csi << 'EOF'
Defaults:csi !requiretty
csi ALL=(ALL) NOPASSWD: /sbin/zfs *, /usr/bin/zfs *, /usr/bin/targetcli *
EOF
chmod 440 /etc/sudoers.d/csi

# 6. SSH鍵の登録
#    ZFSスナップショット転送用の鍵(02-zfs-vm-storage.yml で生成済み)を
#    使い回す。k8s VM上の /root/.ssh/zfs_backup_ed25519.pub の内容を
#    貼り付ける。
mkdir -p /home/csi/.ssh
cat >> /home/csi/.ssh/authorized_keys << 'EOF'
<k8s VM上の /root/.ssh/zfs_backup_ed25519.pub の内容を貼り付け>
EOF
chown -R csi:csi /home/csi/.ssh
chmod 700 /home/csi/.ssh
chmod 600 /home/csi/.ssh/authorized_keys
```

### k8s側のSecret作成

Democratic-CSIドライバー設定(SSH秘密鍵含む)をSecretとして登録する。
k8s VM上の `/root/.ssh/zfs_backup_ed25519` の内容を使用する。

```bash
# k8s VM上でSecretを作成
kubectl create namespace democratic-csi

kubectl create secret generic democratic-csi-driver-config \
  -n democratic-csi \
  --from-file=driver-config-file.yaml=/dev/stdin << 'EOF'
driver: zfs-generic-iscsi
sshConnection:
  host: 192.168.1.97
  port: 22
  username: csi
  privateKey: |
    <k8s VM上の /root/.ssh/zfs_backup_ed25519 の内容を貼り付け>
zfs:
  cli:
    sudoEnabled: true
  datasetParentName: zpool/iris-iscsi
  detachedSnapshotsDatasetParentName: zpool/iris-iscsi-snaps
iscsi:
  shareStrategy: targetCli
  shareStrategyTargetCli:
    sudoEnabled: true
    basename: "iqn.2026-08.internal.proxmox.fox"
    tpg:
      attributes:
        authentication: 0
        generate_node_acls: 1
        demo_mode_write_protect: 0
  targetPortal: "192.168.1.97:3260"
  interface: ""
EOF
```

### k8sノードからの疎通確認

```bash
# k8s VM(iris-k8s-wk-1 等)から実行
# open-iscsi は ansible の 01-prereqs.yml(common ロール)で全ノードに導入済み

# iSCSIターゲットの検出
iscsiadm -m discovery -t sendtargets -p 192.168.1.97:3260
```

### k8s側での利用

[k8s-manifests](https://github.com/sota2501/k8s-manifests)側の
Democratic-CSI Helmチャート(infrastructure/democratic-csi)がStorageClass `zpool-iscsi`
を作成する。PVCで`storageClass: zpool-iscsi`を指定すると、fox上にzvol作成→
iSCSIターゲット公開→ノードでext4フォーマット・マウントが自動で行われる。

## 現状

雛形のみ。VMテンプレート作成手順(cloud-init対応、Packer化など)や、実Proxmox環境での
動作確認はこれから。
