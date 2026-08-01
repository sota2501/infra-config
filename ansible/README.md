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
roles/                            各ステップの実タスク
```

## 現状

雛形のみ。単一 control-plane 構成を前提にしている。HA 化(kube-vip 等)や
テンプレート作成の自動化(Packer)は今後の課題。
