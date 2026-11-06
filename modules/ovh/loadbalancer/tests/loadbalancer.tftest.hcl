# Tests du module loadbalancer : membres, HTTPS activable (count + ternaire)
mock_provider "openstack" {}

variables {
  name_prefix      = "test"
  vip_subnet_id    = "subnet-web"
  member_subnet_id = "subnet-web"
  members = {
    "web-1" = "10.10.1.10"
    "web-2" = "10.10.1.11"
  }
}

run "http_seulement" {
  command = apply

  assert {
    condition     = length(openstack_lb_member_v2.web) == 2
    error_message = "Deux membres HTTP attendus."
  }
  assert {
    condition     = length(openstack_lb_listener_v2.https) == 0
    error_message = "Aucun listener HTTPS quand enable_https = false."
  }
}

run "https_active" {
  command = apply
  variables {
    enable_https      = true
    health_check_path = "/health"
  }

  assert {
    condition     = length(openstack_lb_member_v2.https) == 2
    error_message = "Deux membres HTTPS attendus."
  }
  assert {
    condition     = openstack_lb_listener_v2.https[0].protocol_port == 443
    error_message = "Le listener HTTPS doit écouter sur 443."
  }
  assert {
    condition     = openstack_lb_monitor_v2.https[0].url_path == "/health"
    error_message = "Le health check HTTPS doit viser /health."
  }
  assert {
    condition     = output.https_url != null
    error_message = "L'output https_url doit être renseigné."
  }
}
