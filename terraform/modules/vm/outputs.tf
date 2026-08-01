output "name" {
  value = proxmox_virtual_environment_vm.this.name
}

output "ip_address" {
  description = "CIDR 表記から抽出した IP アドレス(Ansible inventory 生成用)"
  value       = split("/", var.ip_cidr)[0]
}
