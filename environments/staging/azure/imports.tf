import {
  to = module.stack.module.network.azurerm_virtual_network.this
  id = "/subscriptions/b77deef6-f578-47a8-a705-5a07fc4adc00/resourceGroups/myapp-staging-rg/providers/Microsoft.Network/virtualNetworks/myapp-staging-vnet"
}

import {
  to = module.stack.module.load_balancer.azurerm_public_ip.this
  id = "/subscriptions/b77deef6-f578-47a8-a705-5a07fc4adc00/resourceGroups/myapp-staging-rg/providers/Microsoft.Network/publicIPAddresses/myapp-staging-lb-ip"
}

import {
  to = module.stack.module.security.azurerm_network_security_group.this["db"]
  id = "/subscriptions/b77deef6-f578-47a8-a705-5a07fc4adc00/resourceGroups/myapp-staging-rg/providers/Microsoft.Network/networkSecurityGroups/myapp-staging-db-nsg"
}

import {
  to = module.stack.module.security.azurerm_network_security_group.this["web"]
  id = "/subscriptions/b77deef6-f578-47a8-a705-5a07fc4adc00/resourceGroups/myapp-staging-rg/providers/Microsoft.Network/networkSecurityGroups/myapp-staging-web-nsg"
}
