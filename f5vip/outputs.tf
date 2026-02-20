output "vip_assignments" {
  description = "VIP → service mapping"
  value = {
    "solo.rooster.maniak.com"         = "${local.vips["solo_rooster"]}:8080  → agentgateway-proxy (NodePort ${local.nodeports["solo_rooster"]})"
    "argo.rooster.maniak.io (HTTPS)"  = "${local.vips["argo_rooster"]}:443  → argocd-server (NodePort ${local.nodeports["argo_https"]})"
    "argo.rooster.maniak.io (HTTP)"   = "${local.vips["argo_rooster"]}:80   → argocd-server (NodePort ${local.nodeports["argo_http"]})"
    "xai-gateway"                     = "${local.vips["xai_gateway"]}:8081  → xai-gateway-proxy (NodePort ${local.nodeports["xai_gateway"]})"
    "mcp-gateway"                     = "${local.vips["mcp_gateway"]}:8090  → mcp-gateway-proxy (NodePort ${local.nodeports["mcp_gateway"]})"
    "model-priority-gateway"          = "${local.vips["model_gw"]}:8085     → model-priority-gateway-proxy (NodePort ${local.nodeports["model_gw"]})"
    "github-gateway"                  = "${local.vips["github_gw"]}:8092    → github-gateway-proxy (NodePort ${local.nodeports["github_gw"]})"
  }
}
