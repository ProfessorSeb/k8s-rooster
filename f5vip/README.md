# F5 BIG-IP VIPs for Rooster Cluster

Terraform configuration for F5 BIG-IP virtual servers fronting the k8s-rooster Talos cluster.

**BIG-IP:** 172.16.10.10 — **v21.0.0** (upgraded from 17.5.1.3 on 2026-02-20)

All gateway VIPs are **Layer 4 (fastL4)** using existing Kubernetes NodePorts.

## VIP Assignments

| VIP IP | Port | Service | DNS |
|--------|------|---------|-----|
| 172.16.20.120 | 8080 | agentgateway-proxy (NP 31572) | solo.rooster.maniak.com |
| 172.16.20.121 | 443/80 | argocd-server (NP 31988/32178) | argo.rooster.maniak.io |
| 172.16.20.122 | 8081 | xai-gateway-proxy (NP 31990) | — |
| 172.16.20.123 | 8090 | mcp-gateway-proxy (NP 30168) | — |
| 172.16.20.124 | 8085 | model-priority-gateway-proxy (NP 30689) | — |
| 172.16.20.125 | 8092 | github-gateway-proxy (NP 31313) | — |

## Pool Members

All 4 Talos nodes: `172.16.10.130`, `172.16.10.132`, `172.16.10.133`, `172.16.10.136`

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your BIG-IP credentials

terraform init
terraform plan
terraform apply
```

## Notes

- NodePorts are hardcoded from current cluster state — update if services are recreated
- Gateway VIPs use the same port as the original service listener for simplicity
- ArgoCD gets both 443 (TLS passthrough) and 80
