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
playbooks/02-zfs-vm-storage.yml  worker内ZFSストレージ・PVCバックアップの構築
playbooks/03-kubeadm-init.yml    control-plane 初期化
playbooks/04-kubeadm-join.yml    worker の join
playbooks/05-cni.yml             Calico インストール
playbooks/06-argocd-bootstrap.yml  ArgoCD インストール + root Application apply
playbooks/07-image-pull-secrets.yml  private レジストリ用 imagePullSecrets 登録
roles/                            各ステップの実タスク
```

## ZFS PVCバックアップ(playbooks/02-zfs-vm-storage.yml)

worker(iris-k8s-wk-1)のscsi1データディスクをZFSプール(`iris-node`)化し、OpenEBS ZFS LocalPV
(k8s-manifests側)のバックエンドにする。さらにPVC単位でスナップショットを取り、
Proxmoxホスト fox のバックアップ用HDDプールへ日次で増分`zfs send/receive`する。

このplaybook実行前に、**fox側の設定を手動で行っておく必要がある**
(意図的にAnsible管理外にしている。ワークロードが動くVMからハイパーバイザー
ホストへ任意コマンド実行可能なSSHを許可するのはリスクが大きいため、
`command=`で実行コマンドをホワイトリスト化した専用ユーザーのみを使う設計)。

### fox側の手動手順

接続先: `192.168.1.97`、既存バックアップ用プール: `zpool_backup`(HDD)

```bash
# 1. バックアップ受信用データセットの作成(ノード番号はwk-Nに対応)
zfs create zpool_backup/iris-node-1

# 2. 受信専用の非rootユーザーを作成
useradd -m -s /bin/bash zfsbackup

# 3. ラッパースクリプトの作成(実行できるコマンドを厳密に制限する)
cat > /usr/local/bin/zfs-receive-wrapper.sh << 'SCRIPT'
#!/bin/bash
case "$SSH_ORIGINAL_COMMAND" in
  "zfs receive zpool_backup/iris-node-"*)
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

# 4. k8s VM側の公開鍵を登録(02-zfs-vm-storage.yml実行後にdebug出力される鍵を貼り付け)
mkdir -p /home/zfsbackup/.ssh
cat >> /home/zfsbackup/.ssh/authorized_keys << 'EOF'
command="/usr/local/bin/zfs-receive-wrapper.sh",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty <k8s VM側の公開鍵をここに貼り付け>
EOF
chown -R zfsbackup:zfsbackup /home/zfsbackup/.ssh
chmod 700 /home/zfsbackup/.ssh
chmod 600 /home/zfsbackup/.ssh/authorized_keys

# 5. ZFS権限の委譲(root権限を介さずzfsbackupユーザーだけで完結させる)
zfs allow -u zfsbackup create,receive,mount,destroy,snapshot zpool_backup/iris-node-1
```

## eBPFプログラム用のカーネル設定(roles/common)

k8s-manifests側の`infrastructure/ebpf-dnat-router`(TC ingress eBPFプログラム、DMZ用
外部公開IPのDNAT処理)が、Podが`privileged: true`かつ全capability保持であっても
`Prog section 'tc' rejected: Permission denied (13)!`でロードに失敗する事象が発生した。

原因は`kernel.unprivileged_bpf_disabled`が`2`(Ubuntuのデフォルトでこの値になって
いることが多い)になっていたこと。`roles/common`(`playbooks/01-prereqs.yml`経由、
`k8s_cluster`グループ=全ノード対象)でこれを`0`に設定するタスクを追加した。

**重要**: `kernel.unprivileged_bpf_disabled`は"write once"な特殊なsysctlで、既に`2`に
なっているノードでは`sysctl`コマンドによる動的反映(`reload: true`)が効かない。
`ansible-playbook playbooks/01-prereqs.yml`を実行しても、**対象ノードを再起動しない
限り値は変わらない**。適用後は忘れずに対象ノードを再起動すること。

## 現状

単一 control-plane + 1 worker 構成。HA 化(kube-vip 等)や
テンプレート作成の自動化(Packer)は今後の課題。
