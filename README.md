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
│   ├── shared/                   # Shared gateway, tracing params, otel-collector
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
├── docs/                         # Reference examples and deployment guide
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
- **Telemetry** — `solo-enterprise-telemetry-collector` + ClickHouse in kagent namespace, all tracing routes to `kagent.svc.cluster.local:4317`

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

## Key Decisions

- **Consolidated management UI** in kagent namespace — single deployment serves both kagent and AgentGateway products
- **All tracing routes to kagent namespace** — single telemetry collector for both products
- **MCP policies disabled during development** — re-enable via `policies/kustomization.yaml`
- **AgentGateway for MCP routing** — MCP servers deployed as standard Deployments with HTTP transport, fronted by AgentGateway for security/observability
- **kagent uses RemoteMCPServer** to consume AgentGateway-fronted MCP tools — gets tracing and policy enforcement for free
- **ArgoCD with ServerSideApply** — required for CRDs that preserve unknown fields
- **Separated concerns** — Agent CRs in `agents/`, tool server CRs in `tool-servers/`, slack bot in `slack-bot/`

---

**Last Updated**: February 13, 2026
**Cluster**: maniak-rooster (Talos)
**Cluster Name (mgmt)**: rooster.maniak.io
**Maintainer**: Seb (@sebbycorp)
