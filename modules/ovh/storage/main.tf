# Équivalent d'un disque de données managé Azure : stockage persistant, indépendant de la VM
resource "openstack_blockstorage_volume_v3" "this" {
  for_each = var.volumes

  name        = "${var.name_prefix}-vol-${each.key}"
  size        = each.value.size
  volume_type = each.value.type
}

# Attachement du volume à sa VM
resource "openstack_compute_volume_attach_v2" "this" {
  for_each = var.volumes

  instance_id = each.value.instance_id
  volume_id   = openstack_blockstorage_volume_v3.this[each.key].id
}
