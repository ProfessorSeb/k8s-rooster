# Langfuse Integration — Dual Trace Export

> Send AgentGateway LLM traces to both the Solo Enterprise UI (ClickHouse) **and** Langfuse simultaneously.

## Architecture

```
                                    ┌─────────────────────┐
                                    │   Langfuse           │
                                    │   (OTLP HTTP)        │
                                    │   :3000/api/public   │
                                    └──────────▲──────────┘
                                               │
┌──────────────┐    ┌──────────────────────┐   │   ┌──────────────────────────┐
│ AgentGateway │    │ Langfuse OTel        │   │   │ Solo Enterprise          │
│ Proxies      │───▶│ Collector (fan-out)  │───┤   │ Telemetry Collector      │
│              │    │ agentgateway-system   │   │   │ kagent namespace         │
│ - openai     │    │ :4317 (gRPC)         │   │   │ :4317 (gRPC)             │
│ - anthropic  │    └──────────────────────┘   │   └──────────▲──────────────┘
│ - xai        │                               │              │
│ - mcp-*      │                               └──────────────┘
└──────────────┘                                       │
                                               ┌──────▼──────┐
                                               │  ClickHouse  │
                                               │  (Solo UI)   │
                                               └─────────────┘
```

**How it works:**

1. AgentGateway proxies send traces via gRPC to the **Langfuse OTel Collector** (`langfuse-otel-collector.agentgateway-system:4317`)
2. The fan-out collector exports traces to **two destinations**:
   - **Langfuse** via OTLP HTTP (`http://<langfuse-host>:3000/api/public/otel`)
   - **Solo Enterprise Telemetry Collector** via OTLP gRPC (`solo-enterprise-telemetry-collector.kagent:4317`) → ClickHouse
3. Both UIs show the same traces — Solo Enterprise UI for gateway-specific views, Langfuse for LLM observability

**Why a separate collector?**

The Solo Enterprise telemetry collector's ConfigMap is managed by the kagent Helm chart via ArgoCD. Any manual edits get reverted by self-heal. A standalone fan-out collector avoids fighting ArgoCD while keeping the architecture clean.

## Prerequisites

- AgentGateway Enterprise deployed in `agentgateway-system` namespace
- kagent Enterprise with telemetry collector in `kagent` namespace
- Langfuse instance accessible from the cluster (self-hosted or cloud)
- Langfuse API keys (public key + secret key)

## Setup

### Step 1: Get your Langfuse credentials

From your Langfuse UI → **Settings → API Keys**, grab:
- **Public Key** (e.g., `pk-lf-xxxxx`)
- **Secret Key** (e.g., `sk-lf-xxxxx`)

Base64 encode them as `public_key:secret_key`:

```bash
echo -n "pk-lf-YOUR_PUBLIC_KEY:sk-lf-YOUR_SECRET_KEY" | base64
```

### Step 2: Configure the collector

Edit `gateways/shared/langfuse-collector.yaml`:

1. Update the **Langfuse endpoint** to your Langfuse instance:
   ```yaml
   endpoint: http://<YOUR_LANGFUSE_HOST>:3000/api/public/otel
   ```

2. Update the **Authorization header** with your Base64-encoded credentials:
   ```yaml
   headers:
     Authorization: "Basic <YOUR_BASE64_ENCODED_CREDENTIALS>"
   ```

3. Verify the **kagent collector endpoint** is correct:
   ```yaml
   endpoint: solo-enterprise-telemetry-collector.kagent.svc.cluster.local:4317
   ```

### Step 3: Update AgentGateway tracing

Edit `gateways/shared/tracing-params.yaml` and point the `otlpEndpoint` to the Langfuse fan-out collector:

```yaml
spec:
  rawConfig:
    config:
      tracing:
        otlpEndpoint: grpc://langfuse-otel-collector.agentgateway-system.svc.cluster.local:4317
```

### Step 4: Deploy

If using ArgoCD (like this repo), just push and let it sync:

```bash
git add -A && git commit -m "Add Langfuse trace export" && git push
```

If deploying manually:

```bash
# Deploy the fan-out collector
kubectl apply -f gateways/shared/langfuse-collector.yaml

# Update tracing params
kubectl apply -f gateways/shared/tracing-params.yaml

# Restart AgentGateway proxies to pick up new tracing endpoint
kubectl rollout restart deployment -n agentgateway-system -l gateway.networking.k8s.io/gateway-name
```

### Step 5: Verify

Run the verification script:

```bash
./scripts/verify-langfuse.sh
```

Or manually:

```bash
# 1. Check the fan-out collector is running
kubectl get pods -n agentgateway-system -l app=langfuse-otel-collector

# 2. Send a test LLM request through AgentGateway
curl -s -X POST http://<NODE_IP>:<GATEWAY_PORT>/openai/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4.1-mini","messages":[{"role":"user","content":"Hello, trace test!"}]}'

# 3. Check Langfuse for traces (wait ~15 seconds for propagation)
curl -s http://<LANGFUSE_HOST>:3000/api/public/traces?limit=5 \
  -H "Authorization: Basic <YOUR_CREDENTIALS>" | python3 -m json.tool

# 4. Check collector logs for errors
kubectl logs -n agentgateway-system -l app=langfuse-otel-collector --tail 20
```

## What you see in Langfuse

Each LLM request through AgentGateway appears as a trace with:

| Field | Description |
|-------|-------------|
| `name` | Route path (e.g., `POST /openai/*`) |
| `input` | User prompt messages |
| `output` | Model response |
| `metadata.attributes.gateway` | AgentGateway name |
| `metadata.attributes.route` | HTTPRoute name |
| `metadata.attributes.endpoint` | Backend LLM provider endpoint |
| `metadata.attributes.listener` | Gateway listener name |
| `model` | LLM model used |
| `usage` | Token counts (prompt, completion, total) |

## Files

| File | Description |
|------|-------------|
| `gateways/shared/langfuse-collector.yaml` | OTel Collector deployment (ConfigMap + Deployment + Service) |
| `gateways/shared/tracing-params.yaml` | AgentGateway tracing config (points to fan-out collector) |
| `scripts/verify-langfuse.sh` | Verification script |

## Troubleshooting

### No traces in Langfuse

1. **Check collector logs:** `kubectl logs -n agentgateway-system -l app=langfuse-otel-collector`
2. **Verify network connectivity:** Can the collector pod reach your Langfuse host?
3. **Check credentials:** Wrong API keys will result in 401 errors in collector logs
4. **Check proxy restart:** AgentGateway proxies need to restart after changing `tracing-params.yaml`
5. **Check endpoint:** Langfuse only supports OTLP HTTP (not gRPC) — the collector handles the protocol conversion

### Traces in Solo UI but not Langfuse

The fan-out collector exports to both. If Solo UI works but Langfuse doesn't:
- Check the `otlphttp/langfuse` exporter config (endpoint, auth)
- Look for HTTP errors in collector logs

### ArgoCD keeps reverting changes

The Langfuse collector is deployed via ArgoCD as part of `llm-gateways` app — it won't be reverted. The Solo Enterprise collector ConfigMap is managed by the kagent Helm chart and **will** be reverted. That's why we use a separate collector.

## Cleanup

To remove the Langfuse integration:

1. Revert `tracing-params.yaml` to point back to the kagent collector:
   ```yaml
   otlpEndpoint: grpc://solo-enterprise-telemetry-collector.kagent.svc.cluster.local:4317
   ```
2. Delete `langfuse-collector.yaml` and remove it from the kustomization
3. Push and let ArgoCD sync (or `kubectl delete -f gateways/shared/langfuse-collector.yaml`)
