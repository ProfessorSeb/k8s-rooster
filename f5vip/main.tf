###############################################################################
# Local mappings
###############################################################################

locals {
  # VIP assignments from 172.16.20.120-130 range
  vips = {
    solo_rooster = "172.16.20.120" # solo.rooster.maniak.com (main agentgateway)
    argo_rooster = "172.16.20.121" # argo.rooster.maniak.io (ArgoCD)
    xai_gateway  = "172.16.20.122" # xai-gateway-proxy
    mcp_gateway  = "172.16.20.123" # mcp-gateway-proxy
    model_gw     = "172.16.20.124" # model-priority-gateway-proxy
    github_gw    = "172.16.20.125" # github-gateway-proxy
  }

  # NodePort mappings from live cluster
  nodeports = {
    solo_rooster = 31572 # agentgateway-proxy 8080:31572
    argo_https   = 31988 # argocd-server 443:31988
    argo_http    = 32178 # argocd-server 80:32178
    xai_gateway  = 31990 # xai-gateway-proxy 8081:31990
    mcp_gateway  = 30168 # mcp-gateway-proxy 8090:30168
    model_gw     = 30689 # model-priority-gateway-proxy 8085:30689
    github_gw    = 31313 # github-gateway-proxy 8092:31313
  }

  # Build pool member lists: each node on the relevant NodePort
  pool_members = { for name, port in local.nodeports :
    name => [for ip in var.backend_nodes : "${ip}:${port}"]
  }
}

###############################################################################
# Monitors
###############################################################################

resource "bigip_ltm_monitor" "tcp" {
  name     = "/${var.partition}/rooster_tcp_monitor"
  parent   = "/Common/tcp"
  interval = 10
  timeout  = 31
}

###############################################################################
# Pools
###############################################################################

resource "bigip_ltm_pool" "solo_rooster" {
  name                = "/${var.partition}/pool_solo_rooster"
  load_balancing_mode = "round-robin"
  monitors            = [bigip_ltm_monitor.tcp.name]
}

resource "bigip_ltm_pool_attachment" "solo_rooster" {
  for_each = toset(local.pool_members["solo_rooster"])
  pool     = bigip_ltm_pool.solo_rooster.name
  node     = each.value
}

resource "bigip_ltm_pool" "argo_https" {
  name                = "/${var.partition}/pool_argo_rooster_https"
  load_balancing_mode = "round-robin"
  monitors            = [bigip_ltm_monitor.tcp.name]
}

resource "bigip_ltm_pool_attachment" "argo_https" {
  for_each = toset(local.pool_members["argo_https"])
  pool     = bigip_ltm_pool.argo_https.name
  node     = each.value
}

resource "bigip_ltm_pool" "argo_http" {
  name                = "/${var.partition}/pool_argo_rooster_http"
  load_balancing_mode = "round-robin"
  monitors            = [bigip_ltm_monitor.tcp.name]
}

resource "bigip_ltm_pool_attachment" "argo_http" {
  for_each = toset(local.pool_members["argo_http"])
  pool     = bigip_ltm_pool.argo_http.name
  node     = each.value
}

resource "bigip_ltm_pool" "xai_gateway" {
  name                = "/${var.partition}/pool_xai_gateway"
  load_balancing_mode = "round-robin"
  monitors            = [bigip_ltm_monitor.tcp.name]
}

resource "bigip_ltm_pool_attachment" "xai_gateway" {
  for_each = toset(local.pool_members["xai_gateway"])
  pool     = bigip_ltm_pool.xai_gateway.name
  node     = each.value
}

resource "bigip_ltm_pool" "mcp_gateway" {
  name                = "/${var.partition}/pool_mcp_gateway"
  load_balancing_mode = "round-robin"
  monitors            = [bigip_ltm_monitor.tcp.name]
}

resource "bigip_ltm_pool_attachment" "mcp_gateway" {
  for_each = toset(local.pool_members["mcp_gateway"])
  pool     = bigip_ltm_pool.mcp_gateway.name
  node     = each.value
}

resource "bigip_ltm_pool" "model_gw" {
  name                = "/${var.partition}/pool_model_priority_gateway"
  load_balancing_mode = "round-robin"
  monitors            = [bigip_ltm_monitor.tcp.name]
}

resource "bigip_ltm_pool_attachment" "model_gw" {
  for_each = toset(local.pool_members["model_gw"])
  pool     = bigip_ltm_pool.model_gw.name
  node     = each.value
}

resource "bigip_ltm_pool" "github_gw" {
  name                = "/${var.partition}/pool_github_gateway"
  load_balancing_mode = "round-robin"
  monitors            = [bigip_ltm_monitor.tcp.name]
}

resource "bigip_ltm_pool_attachment" "github_gw" {
  for_each = toset(local.pool_members["github_gw"])
  pool     = bigip_ltm_pool.github_gw.name
  node     = each.value
}

###############################################################################
# Virtual Servers
###############################################################################

# --- solo.rooster.maniak.com (L4 TCP) ---
resource "bigip_ltm_virtual_server" "solo_rooster" {
  name                       = "/${var.partition}/vs_solo_rooster"
  destination                = local.vips["solo_rooster"]
  port                       = 8080
  pool                       = bigip_ltm_pool.solo_rooster.name
  ip_protocol                = "tcp"
  source_address_translation = "automap"
  profiles                   = ["/Common/fastL4"]
}

# --- argo.rooster.maniak.io (HTTPS - L4 passthrough) ---
resource "bigip_ltm_virtual_server" "argo_https" {
  name                       = "/${var.partition}/vs_argo_rooster_https"
  destination                = local.vips["argo_rooster"]
  port                       = 443
  pool                       = bigip_ltm_pool.argo_https.name
  ip_protocol                = "tcp"
  source_address_translation = "automap"
  profiles                   = ["/Common/fastL4"]
}

# --- argo.rooster.maniak.io (HTTP redirect target / optional) ---
resource "bigip_ltm_virtual_server" "argo_http" {
  name                       = "/${var.partition}/vs_argo_rooster_http"
  destination                = local.vips["argo_rooster"]
  port                       = 80
  pool                       = bigip_ltm_pool.argo_http.name
  ip_protocol                = "tcp"
  source_address_translation = "automap"
  profiles                   = ["/Common/fastL4"]
}

# --- xai-gateway-proxy (L4 TCP) ---
resource "bigip_ltm_virtual_server" "xai_gateway" {
  name                       = "/${var.partition}/vs_xai_gateway"
  destination                = local.vips["xai_gateway"]
  port                       = 8081
  pool                       = bigip_ltm_pool.xai_gateway.name
  ip_protocol                = "tcp"
  source_address_translation = "automap"
  profiles                   = ["/Common/fastL4"]
}

# --- mcp-gateway-proxy (L4 TCP) ---
resource "bigip_ltm_virtual_server" "mcp_gateway" {
  name                       = "/${var.partition}/vs_mcp_gateway"
  destination                = local.vips["mcp_gateway"]
  port                       = 8090
  pool                       = bigip_ltm_pool.mcp_gateway.name
  ip_protocol                = "tcp"
  source_address_translation = "automap"
  profiles                   = ["/Common/fastL4"]
}

# --- model-priority-gateway-proxy (L4 TCP) ---
resource "bigip_ltm_virtual_server" "model_gw" {
  name                       = "/${var.partition}/vs_model_priority_gateway"
  destination                = local.vips["model_gw"]
  port                       = 8085
  pool                       = bigip_ltm_pool.model_gw.name
  ip_protocol                = "tcp"
  source_address_translation = "automap"
  profiles                   = ["/Common/fastL4"]
}

# --- github-gateway-proxy (L4 TCP) ---
resource "bigip_ltm_virtual_server" "github_gw" {
  name                       = "/${var.partition}/vs_github_gateway"
  destination                = local.vips["github_gw"]
  port                       = 8092
  pool                       = bigip_ltm_pool.github_gw.name
  ip_protocol                = "tcp"
  source_address_translation = "automap"
  profiles                   = ["/Common/fastL4"]
}
