# Politiques de sécurité pour l'infrastructure Azure
policy {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0.0, < 5.0.0"
    }
  }
}

# Sécurité : aucun NSG ne doit autoriser le SSH depuis Internet
resource_policy "azurerm_network_security_group" "no_public_ssh" {
  enforcement_level = "mandatory"

  locals {
    rules = attrs.security_rule == null ? [] : attrs.security_rule
    public_ssh = [
      for r in local.rules : r.name
      if r.access == "Allow" && r.direction == "Inbound"
      && core::contains(["22", "*"], r.destination_port_range)
      && core::contains(["*", "Internet", "0.0.0.0/0"], r.source_address_prefix)
    ]
  }

  enforce {
    condition     = core::length(local.public_ssh) == 0
    error_message = "NSG ${attrs.name} : le SSH est ouvert depuis Internet (règles ${core::join(", ", local.public_ssh)})."
  }
}
