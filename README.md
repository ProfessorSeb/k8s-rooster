# Kubernetes Environment - Rooster 🐓

> *"Talk to me, Goose."*
> *"Goose is dead. I'm Rooster now. And I brought Kubernetes."*

This repository contains Kubernetes configurations for the `maniak-rooster` Talos-based cluster, managed entirely via ArgoCD. It covers Longhorn storage, Solo AgentGateway (AI gateway), kagent Enterprise (AI agent platform), MCP tool servers, and supporting infrastructure.

## Repository Structure

```
k8s-rooster/
├── manifests/                    # ArgoCD app-of-apps (top-level Applications)
│   ├── agentgateway/             # AgentGateway ArgoCD applications
│   ├── kagent/                   # kagent ArgoCD applications (agents, tool servers, slack bot)
│   └── longhorn/                 # Longhorn deployment
├── gateways/                     # LLM gateway resources
│   ├── shared/                   # Shared gateway, tracing params, otel-collector, Langfuse fan-out collector
│   ├── anthropic/                # Anthropic backend + route
│   ├── openai/                   # OpenAI backend + route
│   ├── xai/                      # xAI backend + route + gateway + rate limiting
│   ├── model-priority/           # OpenAI model failover with priority groups
│   └── kustomization.yaml        # References shared/ + each provider as subdirs
├── mcp/                          # MCP server deployments + AgentGateway routing
│   ├── shared/                   # Default MCP gateway (port 8090)
│   ├── everything/               # Demo MCP server (deployment, service, backend, route)
│   ├── github/                   # GitHub Copilot MCP (gateway, backend, routes)
│   ├── slack/                    # Slack MCP server (gateway, deployment, service, backend, route)
│   ├── excalidraw/               # Excalidraw MCP server
│   └── kustomization.yaml        # References shared/ + each server as subdirs
├── policies/                     # AgentGateway policies (organized by category)
│   ├── pii-protection.yaml
│   ├── prompt-injection.yaml
│   ├── credential-protection.yaml
│   ├── elicitation.yaml
│   └── kustomization.yaml
├── agents/                       # kagent Agent CRs ONLY
│   ├── team-lead-agent.yaml
│   ├── github-issues-agent.yaml
│   ├── github-pr-agent.yaml
│   ├── slackbot-k8s-agent.yaml
│   └── kustomization.yaml
├── tool-servers/                 # Remote MCP tool servers for kagent (via AgentGateway)
│   ├── slack-mcp-remote.yaml
│   ├── github-mcp-remote.yaml
│   └── kustomization.yaml
├── slack-bot/                    # Slack bot deployment + local MCPServer CR
│   ├── deployment.yaml
│   ├── slack-mcp.yaml
│   └── kustomization.yaml
├── kagent/                       # kagent Enterprise Helm chart ArgoCD apps
│   ├── kagent-crds-application.yaml
│   ├── kagent-mgmt-application.yaml
│   ├── kagent-application.yaml
│   └── kustomization.yaml
├── models/                       # Model configs (kagent ModelConfig CRs)
├── archive/                      # Stale raw resource dumps (not referenced by ArgoCD)
├── scripts/                      # Utility scripts
│   └── verify-langfuse.sh        # Verify Langfuse dual-export pipeline
├── f5vip/                        # F5 BIG-IP VIP Terraform configs
│   ├── main.tf                   # Virtual servers, pools, pool members, monitors
│   ├── variables.tf              # BIG-IP connection + backend node variables
│   ├── outputs.tf                # VIP → service mapping output
│   ├── provider.tf               # BIG-IP provider config
│   ├── versions.tf               # Terraform + provider version constraints
│   ├── terraform.tfvars.example  # Example credentials file
│   └── README.md                 # VIP assignment table + usage
├── docs/                         # Reference examples and guides
│   └── langfuse-integration.md   # Langfuse setup tutorial + architecture
└── README.md
```

## Architecture Overview

### Namespaces

| Namespace | Purpose |
|---|---|
| `agentgateway-system` | AgentGateway control plane, proxies, MCP servers, LLM gateways |
| `kagent` | kagent Enterprise (agents, tools, management UI, slack bot, telemetry) |
| `argocd` | ArgoCD GitOps controller |
| `longhorn-system` | Longhorn distributed storage |

### Component Stack

- **AgentGateway** (Solo Enterprise) — AI gateway for LLM traffic, MCP tool proxying, A2A, security policies
- **kagent Enterprise** (Solo/CNCF) — Kubernetes-native AI agent platform with MCP tool integration
- **Consolidated Management UI** — Single `solo-enterprise-ui` in kagent namespace serves both kagent and AgentGateway products
- **Telemetry** — Dual-export trace pipeline: AgentGateway → Langfuse OTel Collector (fan-out) → Langfuse + ClickHouse (Solo UI)

### MCP Tool Flow (AgentGateway)

```
MCP Client → AgentGateway Proxy (Gateway + HTTPRoute) → AgentgatewayBackend → MCP Server (Deployment/Service)
```

### kagent → AgentGateway Integration

```
kagent Agent → RemoteMCPServer CR → AgentGateway Proxy → MCP Server
```

This allows kagent agents to use MCP tools that are fronted by AgentGateway, getting security policies, tracing, and rate limiting for free.

## ArgoCD Applications

| Application | Source Path | Namespace | Description |
|---|---|---|---|
| `kagent-apps` | `kagent/` | argocd | App-of-apps for kagent Helm charts |
| `kagent-agents` | `agents/` | kagent | Agent CRs only |
| `kagent-tool-servers` | `tool-servers/` | kagent | RemoteMCPServer CRs (via AgentGateway) |
| `kagent-slack-bot` | `slack-bot/` | kagent | Slack bot deployment + MCPServer CR |
| `kagent-models` | `models/` | kagent | Model configuration CRs |
| `llm-gateways` | `gateways/` | agentgateway-system | LLM gateways (Anthropic, OpenAI, xAI) |
| `openai-gateway` | `gateways/openai/` | agentgateway-system | OpenAI LLM gateway |
| `anthropic-gateway` | `gateways/anthropic/` | agentgateway-system | Anthropic LLM gateway |
| `xai-gateway` | `gateways/xai/` | agentgateway-system | xAI/Grok LLM gateway + rate limiting |
| `model-priority-gateway` | `gateways/model-priority/` | agentgateway-system | OpenAI model failover |
| `mcp-servers` | `mcp/` | agentgateway-system | MCP server deployments + gateways |
| `github-mcp-servers` | `mcp/github/` | agentgateway-system | GitHub MCP (standalone) |
| `agentgateway-policies` | `policies/` | agentgateway-system | Security policies |

All applications use **auto-sync**, **selfHeal**, **prune**, and **ServerSideApply**.

## Quick Commands

```bash
# Check all ArgoCD apps
kubectl get applications -n argocd

# Check AgentGateway proxies
kubectl get gateways -n agentgateway-system

# Check MCP backends and tools
kubectl get agentgatewaybackends -n agentgateway-system
kubectl get remotemcpservers -n kagent

# Check kagent agents
kubectl get agents -n kagent

# Check policies
kubectl get agentgatewaypolicies -n agentgateway-system

# Force ArgoCD sync
kubectl annotate app <app-name> -n argocd argocd.argoproj.io/refresh=hard --overwrite
```

## Tracing & Observability

### Architecture

```
AgentGateway Proxies ──▶ Langfuse OTel Collector (fan-out) ──┬──▶ Langfuse (OTLP HTTP)
                         agentgateway-system:4317             └──▶ Solo Telemetry Collector → ClickHouse (Solo UI)
                                                                   kagent:4317
```

All LLM traces from AgentGateway are dual-exported to both **Langfuse** and the **Solo Enterprise UI** (ClickHouse). A lightweight OTel Collector in `agentgateway-system` acts as a fan-out, forwarding traces to both destinations.

### Components

| Component | Namespace | Purpose |
|---|---|---|
| `langfuse-otel-collector` | agentgateway-system | Fan-out: receives traces from proxies, exports to Langfuse + kagent |
| `solo-enterprise-telemetry-collector` | kagent | Receives traces from fan-out, stores in ClickHouse |
| `kagent-mgmt-clickhouse` | kagent | Trace storage for Solo Enterprise UI |
| Langfuse (external) | Docker on host | LLM observability UI (`http://172.16.10.173:3000`) |

### Configuration

- **Tracing endpoint:** `gateways/shared/tracing-params.yaml` → points to fan-out collector
- **Fan-out collector:** `gateways/shared/langfuse-collector.yaml` → ConfigMap + Deployment + Service
- **Full tutorial:** [`docs/langfuse-integration.md`](docs/langfuse-integration.md)
- **Verification script:** [`scripts/verify-langfuse.sh`](scripts/verify-langfuse.sh)

### Trace Fields in Langfuse

| Field | Example |
|---|---|
| Trace name | `POST /openai/*` |
| Input | User prompt messages |
| Output | Model response |
| Gateway | `agentgateway-system/agentgateway-proxy` |
| Route | `agentgateway-system/openai` |
| Endpoint | `api.openai.com:443` |
| Model | `gpt-4o-mini-2024-07-18` |
| Token usage | Prompt, completion, total |

## F5 BIG-IP VIPs

All services are exposed via F5 BIG-IP virtual servers using Layer 4 (fastL4) profiles, backed by Kubernetes NodePorts across all Talos nodes. Managed via Terraform in `f5vip/`.

| DNS | VIP IP | Port | Backend Service |
|-----|--------|------|-----------------|
| `solo.rooster.maniak.com` | 172.16.20.120 | 8080 | agentgateway-proxy (NP 31572) |
| `argo.rooster.maniak.io` | 172.16.20.121 | 443/80 | argocd-server (NP 31988/32178) |
| `xai.rooster.maniak.com` | 172.16.20.122 | 8081 | xai-gateway-proxy (NP 31990) |
| `mcp.rooster.maniak.com` | 172.16.20.123 | 8090 | mcp-gateway-proxy (NP 30168) |
| `model.rooster.maniak.com` | 172.16.20.124 | 8085 | model-priority-gateway-proxy (NP 30689) |
| `github.rooster.maniak.com` | 172.16.20.125 | 8092 | github-gateway-proxy (NP 31313) |

**Pool members:** All 4 Talos nodes (172.16.10.130, .132, .133, .136)
**DNS:** Managed on FortiGate (172.16.10.1) DNS server for maniak.com and maniak.io zones
**BIG-IP:** 172.16.10.10

```bash
cd f5vip/
cp terraform.tfvars.example terraform.tfvars  # add BIG-IP creds
terraform init && terraform apply
```

## Key Decisions

- **Consolidated management UI** in kagent namespace — single deployment serves both kagent and AgentGateway products
- **Dual trace export via fan-out collector** — separate OTel Collector avoids fighting ArgoCD's Helm-managed ConfigMap while sending traces to both Langfuse and ClickHouse
- **MCP policies disabled during development** — re-enable via `policies/kustomization.yaml`
- **AgentGateway for MCP routing** — MCP servers deployed as standard Deployments with HTTP transport, fronted by AgentGateway for security/observability
- **kagent uses RemoteMCPServer** to consume AgentGateway-fronted MCP tools — gets tracing and policy enforcement for free
- **ArgoCD with ServerSideApply** — required for CRDs that preserve unknown fields
- **Separated concerns** — Agent CRs in `agents/`, tool server CRs in `tool-servers/`, slack bot in `slack-bot/`

---

**Last Updated**: February 20, 2026
**Cluster**: maniak-rooster (Talos)
**Cluster Name (mgmt)**: rooster.maniak.io
**Maintainer**: Seb (@sebbycorp)
