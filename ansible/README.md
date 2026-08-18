# ansible

Terraform で作成した VM に対して、OS セットアップ・kubeadm によるクラスタ構築・
ArgoCD のインストールまでを行う。

GitOpsで実際に同期されるマニフェスト本体は別リポジトリ([k8s-manifests](https://github.com/sota2501/k8s-manifests))
にある。`argocd_bootstrap`ロールは`group_vars/all.yml`の`gitops_repo`/`gitops_repo_branch`を使って
そのリポジトリの`apps/root-app.yaml`を直接取得・applyする(このリポジトリからは読まない)。

## 前提

- `../terraform` で VM を作成済みで、`inventory/home/hosts.yml` の `ansible_host` を
  実際の IP に更新済みであること
- 対象 VM に Ansible 実行ユーザーの SSH 公開鍵(terraform 側で cloud-init 経由で登録)でログインできること
- コントロールノード側に collection をインストール済みであること

  ```sh
  ansible-galaxy collection install -r requirements.yml
  ```

## 使い方(想定)

```sh
# 疎通確認
ansible -m ping all

# フル実行
ansible-playbook playbooks/site.yml

# 個別ステップのみ実行したい場合
ansible-playbook playbooks/01-prereqs.yml
```

## 構成

```
inventory/home/hosts.yml        control_plane / workers のホスト一覧
inventory/home/group_vars/all.yml  k8sバージョン, Pod CIDR 等の共通変数
playbooks/01-prereqs.yml         OS共通設定・containerd・kubernetesパッケージ
playbooks/02-kubeadm-init.yml    control-plane 初期化
playbooks/03-kubeadm-join.yml    worker の join
playbooks/04-cni.yml             Calico インストール
playbooks/05-argocd-bootstrap.yml  ArgoCD インストール + root Application apply
playbooks/06-image-pull-secrets.yml  private レジストリ用 imagePullSecrets 登録
playbooks/07-zfs-vm-storage.yml  worker内ZFSストレージ・PVCバックアップの構築
roles/                            各ステップの実タスク
```

## ZFS PVCバックアップ(playbooks/07-zfs-vm-storage.yml)

worker(iris-k8s-wk-1)のscsi1データディスクをZFSプール化し、OpenEBS ZFS LocalPV
(k8s-manifests側)のバックエンドにする。さらにPVC単位でスナップショットを取り、
Proxmoxホスト rabbit のバックアップ用HDDプールへ日次で増分`zfs send/receive`する。

このplaybook実行前に、**rabbit側の設定を手動で行っておく必要がある**
(意図的にAnsible管理外にしている。ワークロードが動くVMからハイパーバイザー
ホストへ任意コマンド実行可能なSSHを許可するのはリスクが大きいため、
`command=`で実行コマンドをホワイトリスト化した専用ユーザーのみを使う設計)。

### rabbit側の手動手順

接続先: `192.168.1.96`、既存バックアップ用プール: `zpool_backup`(HDD)

```bash
# 1. バックアップ受信用データセットの作成
zfs create zpool_backup/k8s-pool

# 2. 受信専用の非rootユーザーを作成
useradd -m -s /bin/bash zfsbackup

# 3. ラッパースクリプトの作成(実行できるコマンドを厳密に制限する)
cat > /usr/local/bin/zfs-receive-wrapper.sh << 'SCRIPT'
#!/bin/bash
case "$SSH_ORIGINAL_COMMAND" in
  "zfs receive zpool_backup/k8s-pool/"*)
    # シェルメタ文字の混入を拒否(コマンドインジェクション対策)
    if [[ "$SSH_ORIGINAL_COMMAND" =~ [\;\|\&\$\`\(\)\<\>] ]]; then
      echo "invalid characters in command" >&2
      exit 1
    fi
    exec $SSH_ORIGINAL_COMMAND
    ;;
  *)
    echo "command not allowed: $SSH_ORIGINAL_COMMAND" >&2
    exit 1
    ;;
esac
SCRIPT
chmod 755 /usr/local/bin/zfs-receive-wrapper.sh

# 4. k8s VM側の公開鍵を登録(07-zfs-vm-storage.yml実行後にdebug出力される鍵を貼り付け)
mkdir -p /home/zfsbackup/.ssh
cat >> /home/zfsbackup/.ssh/authorized_keys << 'EOF'
command="/usr/local/bin/zfs-receive-wrapper.sh",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty <k8s VM側の公開鍵をここに貼り付け>
EOF
chown -R zfsbackup:zfsbackup /home/zfsbackup/.ssh
chmod 700 /home/zfsbackup/.ssh
chmod 600 /home/zfsbackup/.ssh/authorized_keys

# 5. ZFS権限の委譲(root権限を介さずzfsbackupユーザーだけで完結させる)
zfs allow -u zfsbackup create,receive,mount,destroy,snapshot zpool_backup/k8s-pool
```

## 現状

単一 control-plane + 1 worker 構成。HA 化(kube-vip 等)や
テンプレート作成の自動化(Packer)は今後の課題。
