# count + ternaire : on ne cherche la taille que si elle est précisée
data "openstack_lb_flavor_v2" "this" {
  count = var.flavor_name != null ? 1 : 0
  name  = var.flavor_name
}

# Équivalent de l'Azure Load Balancer
resource "openstack_lb_loadbalancer_v2" "this" {
  name          = "${var.name_prefix}-lb"
  vip_subnet_id = var.vip_subnet_id
  flavor_id     = one(data.openstack_lb_flavor_v2.this[*].id)
}

# Écoute HTTP sur le port 80
resource "openstack_lb_listener_v2" "http" {
  name            = "${var.name_prefix}-listener-http"
  loadbalancer_id = openstack_lb_loadbalancer_v2.this.id
  protocol        = "HTTP"
  protocol_port   = var.port
}

# Groupe de serveurs, répartition à tour de rôle
resource "openstack_lb_pool_v2" "web" {
  name        = "${var.name_prefix}-pool-web"
  listener_id = openstack_lb_listener_v2.http.id
  protocol    = "HTTP"
  lb_method   = "ROUND_ROBIN"
}

# Un membre par serveur web
resource "openstack_lb_member_v2" "web" {
  for_each = var.members

  name          = "${var.name_prefix}-member-${each.key}"
  pool_id       = openstack_lb_pool_v2.web.id
  address       = each.value
  protocol_port = var.port
  subnet_id     = var.member_subnet_id
}

# Health check : un serveur qui ne répond plus est retiré du pool
resource "openstack_lb_monitor_v2" "web" {
  name        = "${var.name_prefix}-monitor-web"
  pool_id     = openstack_lb_pool_v2.web.id
  type        = "HTTP"
  url_path    = var.health_check_path
  delay       = 5
  timeout     = 3
  max_retries = 3
}

# IP publique du Load Balancer (équivalent de la Public IP Azure)
resource "openstack_networking_floatingip_v2" "lb" {
  pool        = var.external_network_name
  description = "${var.name_prefix} - IP publique du Load Balancer"
}

resource "openstack_networking_floatingip_associate_v2" "lb" {
  floating_ip = openstack_networking_floatingip_v2.lb.address
  port_id     = openstack_lb_loadbalancer_v2.this.vip_port_id
}

# --- HTTPS en passthrough : le Load Balancer ne déchiffre pas, il transmet ---

resource "openstack_lb_listener_v2" "https" {
  count = var.enable_https ? 1 : 0

  name            = "${var.name_prefix}-listener-https"
  loadbalancer_id = openstack_lb_loadbalancer_v2.this.id
  protocol        = "HTTPS"
  protocol_port   = 443
}

resource "openstack_lb_pool_v2" "https" {
  count = var.enable_https ? 1 : 0

  name        = "${var.name_prefix}-pool-https"
  listener_id = openstack_lb_listener_v2.https[0].id
  protocol    = "HTTPS"
  lb_method   = "ROUND_ROBIN"
}

resource "openstack_lb_member_v2" "https" {
  for_each = var.enable_https ? var.members : {}

  name          = "${var.name_prefix}-member-https-${each.key}"
  pool_id       = openstack_lb_pool_v2.https[0].id
  address       = each.value
  protocol_port = 443
  subnet_id     = var.member_subnet_id
}

# Health check HTTPS : vérifie que nginx répond en TLS
resource "openstack_lb_monitor_v2" "https" {
  count = var.enable_https ? 1 : 0

  name        = "${var.name_prefix}-monitor-https"
  pool_id     = openstack_lb_pool_v2.https[0].id
  type        = "HTTPS"
  url_path    = var.health_check_path
  delay       = 5
  timeout     = 3
  max_retries = 3
}
