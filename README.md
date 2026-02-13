# Kubernetes Environment - Rooster

This repository contains Kubernetes configurations for the `maniak-rooster` Talos-based cluster, managed entirely via ArgoCD. It covers Longhorn storage, Solo AgentGateway (AI gateway), kagent Enterprise (AI agent platform), MCP tool servers, and supporting infrastructure.

## Repository Structure

```
k8s-rooster/
├── manifests/                    # ArgoCD app-of-apps (top-level Applications)
│   ├── agentgateway/             # AgentGateway ArgoCD applications
│   ├── kagent/                   # kagent ArgoCD applications (agents, tool servers)
│   └── longhorn/                 # Longhorn deployment
├── configs/                      # AgentGateway CRDs and base configs
│   └── agentgateway/
├── gateways/                     # LLM gateway resources (Gateway, HTTPRoute, Backend, tracing)
│   ├── anthropic/
│   ├── openai/
│   ├── xai/
│   ├── otel-collector/
│   └── tracing-params.yaml       # Shared EnterpriseAgentgatewayParameters for tracing
├── mcp/                          # MCP server deployments + AgentGateway routing
│   ├── mcp-server-everything/    # Demo MCP server (echo, get-env, etc.)
│   ├── github/                   # GitHub Copilot MCP (static backend via api.githubcopilot.com)
│   ├── slack/                    # Slack MCP server (Deployment + Service + Backend + Route + Gateway)
│   ├── backend/                  # Shared MCP backend
│   ├── routes/                   # Shared MCP routes
│   ├── gateway.yaml              # Default MCP gateway (port 8090)
│   └── kustomization.yaml
├── policies/                     # AgentGateway policies (PII guards, jailbreak, elicit, MCP tool auth)
│   └── kustomization.yaml        # All MCP policies currently disabled
├── kagent/                       # kagent Enterprise Helm chart ArgoCD apps
│   ├── kagent-crds-application.yaml
│   ├── kagent-mgmt-application.yaml    # Management UI (serves both kagent + agentgateway)
│   ├── kagent-application.yaml
│   └── kustomization.yaml
├── agents/                       # kagent Agent CRs, MCPServer CRs, Slack bot
│   ├── slackbot-k8s-agent.yaml
│   ├── kagent-slack-bot-deployment.yaml
│   ├── slack-mcp.yaml            # MCPServer CR (stdio transport, kagent-managed)
│   └── kustomization.yaml
├── kagent-tool-servers/          # Remote MCP tool servers for kagent (via AgentGateway)
│   ├── slack-mcp-remote.yaml     # RemoteMCPServer → AgentGateway slack MCP proxy
│   └── kustomization.yaml
└── README.md
```

## Architecture Overview

### Namespaces

| Namespace | Purpose |
|---|---|
| `agentgateway-system` | AgentGateway control plane, proxies, MCP servers, LLM gateways |
| `kagent` | kagent Enterprise (agents, tools, management UI, telemetry collector, ClickHouse) |
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
| `kagent-crds` | Helm chart | kagent | kagent Enterprise CRDs (v0.3.4) |
| `kagent-mgmt` | Helm chart | kagent | Management UI + telemetry (both products) |
| `kagent` | Helm chart | kagent | kagent Enterprise controller (v0.3.4) |
| `kagent-agents` | `agents/` | kagent | Agent CRs, MCPServer CRs, Slack bot |
| `kagent-tool-servers` | `kagent-tool-servers/` | kagent | RemoteMCPServer CRs (via AgentGateway) |
| `llm-gateways` | `gateways/` | agentgateway-system | LLM gateways (Anthropic, OpenAI, xAI) |
| `openai-gateway` | `gateways/openai/` | agentgateway-system | OpenAI LLM gateway |
| `anthropic-gateway` | `gateways/anthropic/` | agentgateway-system | Anthropic LLM gateway |
| `xai-gateway` | `gateways/xai/` | agentgateway-system | xAI/Grok LLM gateway |
| `mcp-servers` | `mcp/` | agentgateway-system | MCP server deployments + gateways |
| `agentgateway-policies` | `policies/` | agentgateway-system | Security policies (MCP policies currently disabled) |

All applications use **auto-sync**, **selfHeal**, **prune**, and **ServerSideApply**.

## MCP Servers

### mcp-server-everything (Demo)
- **Namespace:** agentgateway-system
- **Gateway:** `mcp-gateway-proxy:8090`
- **Path:** `/mcp`
- **Tools:** echo, get-env, sample tools

### GitHub MCP (Copilot)
- **Namespace:** agentgateway-system
- **Gateway:** `gh-mcp-gateway-proxy:8091`
- **Backend:** Static → `api.githubcopilot.com:443` (TLS)
- **Path:** `/mcp-github`
- **Auth:** Bearer token via HTTPRoute filter (from `ph-secret`)

### Slack MCP
- **Namespace:** agentgateway-system
- **Gateway:** `mcp-slack-gateway-proxy:8079`
- **Path:** `/mcp/slack`
- **Image:** `zencoderai/slack-mcp:latest` (HTTP transport)
- **Auth:** Static Bearer token (`agentgateway-internal`) injected via HTTPRoute filter
- **Secrets:** `slack-credentials` (SLACK_APP_TOKEN, SLACK_BOT_TOKEN, SLACK_CHANNEL_IDS, SLACK_TEAM_ID)
- **kagent integration:** `RemoteMCPServer` CR `slack-mcp-agentgateway` in kagent namespace
- **Discovered tools:** `slack_list_channels`, `slack_post_message`, `slack_reply_to_thread`, `slack_add_reaction`, `slack_get_channel_history`, `slack_get_thread_replies`, `slack_get_users`, `slack_get_user_profile`

## kagent Agents

| Agent | Description | Tools |
|---|---|---|
| `k8s-agent` | Kubernetes operations | kagent built-in k8s tools |
| `kgateway-agent` | kGateway/AgentGateway management | kagent built-in tools |
| `helm-agent` | Helm chart operations | kagent built-in tools |
| `slackbot-k8s-agent` | Slack bot agent | k8s tools + Slack MCP |

### Slack Bot
- **Image:** `sebbycorp/kagent-slack-bot:latest`
- **Connects to:** `kagent-controller.kagent.svc.cluster.local:8083`
- **Agent:** `slackbot-k8s-agent`
- **Secrets:** `slack-credentials` in kagent namespace

## Tracing & Observability

All tracing (AgentGateway + kagent) routes to the consolidated telemetry stack in kagent namespace:

- **Collector:** `solo-enterprise-telemetry-collector.kagent.svc.cluster.local:4317` (OTLP gRPC)
- **Storage:** ClickHouse in kagent namespace
- **UI:** Solo Enterprise UI (`solo-enterprise-ui`) in kagent namespace

### Tracing Configuration (`gateways/tracing-params.yaml`)
- Random sampling enabled
- Full gen_ai attributes (model, params, prompt/completion content)
- HTTP context, headers, and LLM-specific fields

## Security Policies

### Active LLM Policies (on LLM gateways)
- PII guards: SSN, credit cards, phone numbers, Canadian SIN
- Jailbreak prevention: instruction ignoring, DAN mode, role manipulation
- Credential leak protection: OpenAI API keys, GitHub tokens, Slack tokens
- Prompt enrichment: security context, compliance, response format, K8s expertise, chain-of-thought

### MCP Policies (currently disabled)
All MCP tool authorization policies are disabled to allow unrestricted tool access during development. Re-enable in `policies/kustomization.yaml` when needed.

## Prerequisites

- Talos-based Kubernetes cluster
- ArgoCD installed and configured
- kubectl with OIDC login configured
- AgentGateway Enterprise license
- kagent Enterprise license
- Slack app credentials (for Slack MCP + bot)

## Secrets Required

| Secret | Namespace | Keys |
|---|---|---|
| `agent-gateway-license` | agentgateway-system | `license-key` |
| `kagent-openai` | kagent | `OPENAI_API_KEY` |
| `slack-credentials` | kagent | `SLACK_APP_TOKEN`, `SLACK_BOT_TOKEN`, `SLACK_CHANNEL_IDS`, `SLACK_TEAM_ID` |
| `slack-credentials` | agentgateway-system | Same keys (copied for MCP server) |
| `ph-secret` | agentgateway-system | `Authorization` (GitHub Copilot Bearer token) |

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

- **Consolidated management UI** in kagent namespace — single deployment serves both kagent and AgentGateway products, avoiding duplicate infrastructure
- **All tracing routes to kagent namespace** — single telemetry collector for both products
- **MCP policies disabled during development** — re-enable via `policies/kustomization.yaml`
- **AgentGateway for MCP routing** — MCP servers deployed as standard Deployments with HTTP transport, fronted by AgentGateway for security/observability
- **kagent uses RemoteMCPServer** to consume AgentGateway-fronted MCP tools — gets tracing and policy enforcement for free
- **ArgoCD with ServerSideApply** — required for CRDs that preserve unknown fields

---

**Last Updated**: February 12, 2026
**Cluster**: maniak-rooster (Talos)
**Cluster Name (mgmt)**: rooster.maniak.io
**Maintainer**: Seb (@sebbycorp)
