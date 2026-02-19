# AgentGateway Enterprise v0.11.1-patch1: xDS push incomplete for MCP Backends with auth policies

## Summary
Control plane pushes only tracing (~35 bytes) to proxy. No listeners, routes, backends, or auth configs translated from CRDs. Proxy receives requests (200 routed) but backends lack auth headers → GitHub MCP returns 0 tools.

Direct to `api.githubcopilot.com/mcp/tools/list`: 41 tools ✅  
Through proxy: 0 tools ❌

## Environment
- AgentGateway Enterprise: v0.11.1-patch1 (Helm OCI us-docker.pkg.dev/solo-public/enterprise-agentgateway/charts/enterprise-agentgateway v2.1.1)
- K8s: Talos (maniak-rooster-jacob), ns agentgateway-system
- Gateway: `mcp-gateway-proxy` listener 8090/HTTP
- Route: `mcp-github` PathPrefix /mcp-github → Backend `github-mcp-backend`
- Backend: mcp target static `api.githubcopilot.com:443 /mcp` with auth `key: Authorization = Bearer <PAT>`

## Reproduction
1. Apply yamls (below)
2. Proxy /config_dump → `{listeners:0, clusters:0, routes:0}`
3. `curl /mcp-github/tools/list` → 200 but empty tools array

## Proxy Config Dump (during bug)
```
{listeners: 0, clusters: 0, routes: 0, size_bytes: ~35}
```
Only tracing pushed. Control plane logs WDS only.

## Tried (no fix)
- secretRef vs key for auth
- No policies at all
- HeaderModifier on Route
- Restarts control plane/proxy
- Different PAT formats

## Workaround
Local `github-mcp-server` + nginx PAT injection → xDS works (no backend auth needed)

## CRDs
### AgentgatewayBackend
```yaml
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayBackend
metadata:
  name: github-mcp-backend
spec:
  mcp:
    targets:
    - name: mcp-target
      static:
        host: api.githubcopilot.com
        path: /mcp
        port: 443
  policies:
    auth:
      key:
        Authorization: Bearer ghp_vyb2zy...
```
Status: Accepted ✅

### HTTPRoute
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: mcp-github
spec:
  parentRefs:
  - name: mcp-gateway-proxy
    sectionName: mcp-gateway
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /mcp-github
    backendRefs:
    - name: github-mcp-backend
```
Status: Accepted/ResolvedRefs ✅

### Gateway
Listener mcp-gateway port 8090 HTTP ✅

## Logs
Proxy: route=agentgateway-system/mcp-github HTTP 200 (but empty response)
Control plane: only WDS responses, no Resource push