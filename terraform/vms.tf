module "control_plane" {
  source = "./modules/vm"

  for_each = var.control_plane_nodes

  name              = each.key
  node_name         = each.value.node_name
  vm_id             = each.value.vm_id
  clone_template_id = var.vm_template_id
  cores             = each.value.cores
  memory            = each.value.memory
  disk_gb           = each.value.disk_gb
  datastore_id      = var.vm_datastore_id
  network_bridge    = var.vm_network_bridge
  ip_cidr           = each.value.ip_cidr
  gateway           = var.network_gateway
  dns_servers       = var.network_dns_servers
  ssh_public_keys   = local.ssh_public_keys
}

module "worker" {
  source = "./modules/vm"

  for_each = var.worker_nodes

  name              = each.key
  node_name         = each.value.node_name
  vm_id             = each.value.vm_id
  clone_template_id = var.vm_template_id
  cores             = each.value.cores
  memory            = each.value.memory
  disk_gb           = each.value.disk_gb
  datastore_id      = var.vm_datastore_id
  network_bridge    = var.vm_network_bridge
  ip_cidr           = each.value.ip_cidr
  gateway           = var.network_gateway
  dns_servers       = var.network_dns_servers
  ssh_public_keys   = local.ssh_public_keys
}
