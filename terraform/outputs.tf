output "control_plane_ips" {
  description = "control-plane ノードの名前 => IP アドレス"
  value       = { for k, v in module.control_plane : k => v.ip_address }
}

output "worker_ips" {
  description = "worker ノードの名前 => IP アドレス"
  value       = { for k, v in module.worker : k => v.ip_address }
}

# TODO: terraform output -json control_plane_ips / worker_ips を使って
# ansible/inventory/home/hosts.yml を生成するスクリプト(scripts/gen-inventory.sh 等)を追加する。
