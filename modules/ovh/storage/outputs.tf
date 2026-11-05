output "volume_ids" {
  description = "IDs des volumes, indexés par nom"
  value       = { for name, vol in openstack_blockstorage_volume_v3.this : name => vol.id }
}

output "devices" {
  description = "Périphériques vus par les VMs (indicatif, le nom réel peut différer dans le système)"
  value       = { for name, att in openstack_compute_volume_attach_v2.this : name => att.device }
}
