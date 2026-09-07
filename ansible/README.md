# ansible

Terraform で作成した VM に対して、OS セットアップ・kubeadm によるクラスタ構築・
ArgoCD のインストールまでを行う。

GitOpsで実際に同期されるマニフェスト本体は別リポジトリ([k8s-manifests](https://github.com/sota2501/k8s-manifests))
にある。`argocd_bootstrap`ロールは`group_vars/all/vars.yml`の`gitops_repo`/`gitops_repo_branch`を
使ってそのリポジトリの`apps/root-app.yaml`を直接取得・applyする(このリポジトリからは読まない)。

## 前提

- `../terraform` で VM を作成済みで、`inventory/home/hosts.yml` の `ansible_host` を
  実際の IP に更新済みであること
- 対象 VM に Ansible 実行ユーザーの SSH 公開鍵(terraform 側で cloud-init 経由で登録)でログインできること
- コントロールノード側に collection をインストール済みであること

  ```sh
  ansible-galaxy collection install -r requirements.yml
  ```

- private リポジトリ・レジストリ用の PAT を用意済みであること

  ```sh
  cp inventory/home/group_vars/all/secrets.yml.example inventory/home/group_vars/all/secrets.yml
  # gitops_repo_token と ghcr_pull_token を実際の値に書き換える
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
ansible.cfg                      inventory / roles_path / become の既定
requirements.yml                 必要な Galaxy コレクション
inventory/home/hosts.yml         control_plane / workers のホスト一覧
inventory/home/group_vars/all/vars.yml     k8sバージョン, Pod CIDR 等の共通変数
inventory/home/group_vars/all/secrets.yml  PAT 等(git 管理外。.example をコピーして作る)
playbooks/01-prereqs.yml         OS共通設定・containerd・kubernetesパッケージ
playbooks/02-zfs-vm-storage.yml  worker内ZFSストレージ・PVCバックアップの構築
playbooks/03-dmz-router.yml     ebpf-dmz-router(eBPF/TCX)のノード導入
playbooks/04-kubeadm-init.yml    control-plane 初期化
playbooks/05-kubeadm-join.yml    worker の join
playbooks/06-cni.yml             Calico インストール
playbooks/07-argocd-bootstrap.yml  ArgoCD インストール + root Application apply
playbooks/08-image-pull-secrets.yml  private レジストリ用 imagePullSecrets 登録
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

## ebpf-dmz-router(playbooks/03-dmz-router.yml)

単一の DMZ IP の背後に複数のサービスをポート単位で公開する eBPF(TCX)ルーターを
ノードへ導入する(`roles/dmz_router`)。設計と仕様は
[ebpf-dmz-router](https://github.com/sota2501/ebpf-dmz-router) リポジトリの
`docs/` にあり、**このロールはその「ノードへの導入」手順を実装したもの**である。
仕様を変更したときは両方を合わせること。

**kubeadm より前(02 と 04 の間)に置いている。** 導入する systemd ユニットは
`Before=kubelet.service` を持ち、kubelet より先に attach して bpffs 上に pin を
作る。クラスタ側の DaemonSet はその pin を hostPath でマウントするため、pin が
無いと Pod が `ContainerCreating` のまま停滞する。先にノード側を成立させて
おけば、この順序依存を気にせずに済む。

**前提として ebpf-dmz-router のリリースが公開されている必要がある。**
ロールは BPF オブジェクトと attach スクリプトを GitHub Release から
(`SHA256SUMS` で検証しながら)取得するため、タグが未発行だと失敗する。
リポジトリが private の間は `secrets.yml` の `gitops_repo_token` が必須で、
未設定だと取得が 404 になる。k8s-manifests と同じ PAT を使うので、**PAT の
対象リポジトリに ebpf-dmz-router を追加し、`Contents: Read` を与えておくこと**。
fine-grained PAT はリポジトリを選ぶだけでは足りず、権限も個別に必要になる。
権限不足のときも(存在を漏らさないため)403 ではなく 404 が返る。

取得は GitHub REST API のアセットエンドポイント経由で行う。ブラウザ用の
`https://github.com/<owner>/<repo>/releases/download/...` は private
リポジトリでは PAT を受け付けず、常に 404 になるため使えない。切り分けは
以下で行う(いずれも 200 が返れば正常)。

```sh
T=<PAT>
# 1. PAT がリポジトリを見えているか(404 ならリポジトリ未追加か権限不足)
curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $T" \
  https://api.github.com/repos/sota2501/ebpf-dmz-router
# 2. 当該リリースが見えているか(アセット ID もここで確認できる)
curl -s -H "Authorization: Bearer $T" \
  https://api.github.com/repos/sota2501/ebpf-dmz-router/releases/tags/v0.1.0 \
  | grep -E '"(name|id)"'
```

クラスタ側(controller の DaemonSet、`dmz-anchor` Service)は k8s-manifests から
ArgoCD 経由で入る。`dmz_router_version` は k8s-manifests の
`kustomization.yaml` の `version` と揃えること。

## `kernel.unprivileged_bpf_disabled`(roles/common)

`roles/common`(`playbooks/01-prereqs.yml`経由、`k8s_cluster`=全ノード対象)が
これを`0`に設定している。**旧設計の名残であり、現在は不要な可能性が高い。**

eBPFプログラムを`privileged: true`のPodからロードしていた頃、Ubuntu既定の`2`が
原因で`Prog section 'tc' rejected: Permission denied (13)!`となる事象があり、
その対処として入れたもの。現在の ebpf-dmz-router は attach をノード上の
systemd(root)が行い、controller は`CAP_BPF`を持つ非rootで動くため、`2`
(非特権からの`bpf()`のみ拒否、`CAP_BPF`は通る)で足りるはずである。`0`は
ノード上の任意の非特権プロセスに`bpf()`を開放するので、検証のうえ外したい。

**"write once"な特殊なsysctlである。** 既に`2`になっているノードでは
`sysctl`の動的反映(`reload: true`)が効かず、値を変えるには対象ノードの
再起動が要る。

## 現状

単一 control-plane + 1 worker 構成。HA 化(kube-vip 等)や
テンプレート作成の自動化(Packer)は今後の課題。
