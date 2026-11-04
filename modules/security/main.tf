# Aplatissement : { web = { rules = { ssh, http } } } devient { "web-ssh" = {...}, "web-http" = {...} }
# Ainsi, chaque règle a une clé stable : en ajouter ou en retirer une ne recrée pas les autres.
locals {
  rules = merge([
    for sg_name, sg in var.security_groups : {
      for rule_name, rule in sg.rules :
      "${sg_name}-${rule_name}" => merge(rule, { sg_name = sg_name, rule_name = rule_name })
    }
  ]...)
}

# Un security group par entrée (web, db...)
resource "openstack_networking_secgroup_v2" "this" {
  for_each = var.security_groups

  name        = "${var.name_prefix}-sg-${each.key}"
  description = each.value.description
}

# Règles entrantes générées dynamiquement
resource "openstack_networking_secgroup_rule_v2" "this" {
  for_each = local.rules

  security_group_id = openstack_networking_secgroup_v2.this[each.value.sg_name].id
  description       = "${each.value.sg_name} - ${each.value.rule_name}"
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = each.value.protocol
  port_range_min    = each.value.port_min
  port_range_max    = each.value.port_max

  # Ternaires : la source est soit une plage d'IP, soit un autre security group
  remote_ip_prefix = each.value.remote_group == null ? each.value.remote_ip_prefix : null
  remote_group_id  = each.value.remote_group != null ? openstack_networking_secgroup_v2.this[each.value.remote_group].id : null
}
