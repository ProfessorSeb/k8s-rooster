# MCP (Model Context Protocol) Servers

Enterprise AgentGateway configuration for MCP servers with dynamic routing and HTTPS connections.

## Overview

This deployment sets up multiple MCP gateways for different MCP server types:

### Local MCP Server
- **MCP Gateway**: Listens on port 8090 for MCP traffic
- **MCP Server**: `mcp-server-everything` providing various utility tools  
- **Dynamic Routing**: Uses label selectors to automatically discover MCP servers
- **Protocol Support**: Streamable HTTP for MCP communication

### GitHub MCP Server (HTTPS)
- **GitHub MCP Gateway**: Listens on port 8091 for GitHub MCP traffic
- **GitHub MCP Server**: Remote connection to `api.githubcopilot.com`
- **Static Routing**: Direct HTTPS connection to GitHub's MCP server
- **Authentication**: Uses GitHub Personal Access Token via `ph-secret`
- **CORS Support**: Configured for browser-based MCP Inspector access

## Architecture

### Local MCP Server
```
AI Client → MCP Gateway (8090) → HTTPRoute (/mcp) → AgentgatewayBackend → MCP Server (3001)
```

### GitHub MCP Server  
```
AI Client → GitHub MCP Gateway (8091) → HTTPRoute (/mcp-github) → AgentgatewayBackend → api.githubcopilot.com:443 (HTTPS)
                                     ↓
                              AgentgatewayPolicy (CORS + Auth Header from ph-secret)
```

## Components

### Gateway Configuration
- **Name**: `mcp-gateway-proxy`
- **Port**: 8090
- **Protocol**: HTTP
- **Tracing**: Enabled via `tracing` parameters

### MCP Server
- **Image**: `node:20-alpine`
- **Package**: `@modelcontextprotocol/server-everything`
- **Protocol**: `streamableHttp`
- **Port**: 3001

### Backend Configuration
- **Type**: Dynamic with label selectors
- **Selector**: `app: mcp-server-everything`
- **Protocol**: MCP via `appProtocol: kgateway.dev/mcp`

### Routing
- **Path**: `/mcp` (configurable via `kgateway.dev/mcp-path` annotation)
- **Parent**: `mcp-gateway-proxy`

## Deployment

### Via ArgoCD (Recommended)
```bash
# Deploy MCP servers application
kubectl apply -f manifests/agentgateway/mcp-application.yaml

# Monitor deployment
kubectl get applications -n argocd
```

### Direct Application
```bash
# Via Kustomize
kubectl apply -k mcp/

# Individual resources
kubectl apply -f mcp/gateway.yaml
kubectl apply -f mcp/mcp-server-everything/
kubectl apply -f mcp/backend/
kubectl apply -f mcp/routes/
```

## Usage

### Get Gateway Addresses
```bash
# Local MCP Server
kubectl get svc mcp-gateway-proxy -n agentgateway-system

# GitHub MCP Server  
kubectl get svc gh-mcp-gateway-proxy -n agentgateway-system
```

### Test with MCP Inspector

**Local MCP Server:**
```bash
# Install MCP Inspector tool
npx @modelcontextprotocol/inspector#0.18.0

# Connect to: http://GATEWAY-IP:8090/mcp
# Transport Type: Streamable HTTP
```

**GitHub MCP Server:**
```bash
# Connect to: http://GATEWAY-IP:8091/mcp-github  
# Transport Type: Streamable HTTP
# Provides GitHub repository, issues, PRs access
```

### Local Testing
```bash
# Port forward for local MCP testing
kubectl port-forward svc/mcp-gateway-proxy -n agentgateway-system 8090:8090
# Connect to: http://localhost:8090/mcp

# Port forward for GitHub MCP testing
kubectl port-forward svc/gh-mcp-gateway-proxy -n agentgateway-system 8091:8091  
# Connect to: http://localhost:8091/mcp-github
```

## Available Tools

The `mcp-server-everything` provides various utility tools:

- **echo**: Echo back messages
- **get_time**: Get current time
- **add_numbers**: Add two numbers
- **list_directory**: List directory contents
- **read_file**: Read file contents
- **write_file**: Write to files
- **And more...**

## Customization

### Add Custom MCP Servers
1. Create new deployment in `mcp/my-custom-server/`
2. Ensure service has `appProtocol: kgateway.dev/mcp`
3. Add appropriate labels for backend selector
4. Update `kustomization.yaml`

### Custom MCP Path
Add annotation to service:
```yaml
annotations:
  kgateway.dev/mcp-path: "/custom-path"
```

### Multiple MCP Servers
Create additional AgentgatewayBackend resources with different label selectors:
```yaml
spec:
  mcp:
    targets:
    - name: server-a
      selector:
        services:
          matchLabels:
            app: mcp-server-a
    - name: server-b  
      selector:
        services:
          matchLabels:
            app: mcp-server-b
```

## Monitoring

### Check Status
```bash
# Gateway status
kubectl get gateway mcp-gateway-proxy -n agentgateway-system

# Backend status  
kubectl get agentgatewaybackend mcp-backend -n agentgateway-system

# Server status
kubectl get pods -l app=mcp-server-everything -n agentgateway-system

# Route status
kubectl get httproute mcp -n agentgateway-system
```

### Logs
```bash
# MCP server logs
kubectl logs -l app=mcp-server-everything -n agentgateway-system -f

# Gateway logs
kubectl logs -l agentgateway=agentgateway -n agentgateway-system -f
```

## Troubleshooting

| Issue | Check |
|-------|-------|
| MCP connection fails | Service has `appProtocol: kgateway.dev/mcp` |
| Backend not found | Label selectors match service labels |
| 404 errors | HTTPRoute path matches gateway listener |
| Gateway not ready | EnterpriseAgentgatewayParameters exists |

## References

- [Solo.io MCP Documentation](https://docs.solo.io/agentgateway/2.1.x/mcp/dynamic-mcp/)
- [Model Context Protocol Specification](https://modelcontextprotocol.io/)
- [MCP Inspector Tool](https://modelcontextprotocol.io/docs/tools/inspector)