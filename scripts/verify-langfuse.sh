#!/usr/bin/env bash
# verify-langfuse.sh — Verify Langfuse dual-export trace pipeline
#
# Usage: ./scripts/verify-langfuse.sh [NODE_IP] [GATEWAY_PORT]
#
# Defaults:
#   NODE_IP=172.16.10.168
#   GATEWAY_PORT=31572 (agentgateway-proxy NodePort)

set -euo pipefail

NODE_IP="${1:-172.16.10.168}"
GATEWAY_PORT="${2:-31572}"
LANGFUSE_ENDPOINT="http://172.16.10.173:3000"
LANGFUSE_AUTH="Basic cGstbGYtNmEyODVjZjUtMjc4Ny00Y2Y3LTgyM2ItNTRmZWY5YmIxYjYwOnNrLWxmLTE5NDI2ZWRlLTMyYWItNGFlMS05YTM0LTY0MjkwMDA5MDE4ZA=="
KUBECTL_CTX="${KUBECTL_CONTEXT:-}"

kubectl_cmd() {
  if [[ -n "$KUBECTL_CTX" ]]; then
    kubectl --context "$KUBECTL_CTX" "$@"
  else
    kubectl "$@"
  fi
}

echo "============================================"
echo "  Langfuse Dual-Export Verification"
echo "============================================"
echo ""

# Step 1: Check fan-out collector
echo "1️⃣  Checking Langfuse OTel Collector..."
COLLECTOR_STATUS=$(kubectl_cmd get pods -n agentgateway-system -l app=langfuse-otel-collector -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
if [[ "$COLLECTOR_STATUS" == "Running" ]]; then
  echo "   ✅ langfuse-otel-collector is Running"
else
  echo "   ❌ langfuse-otel-collector status: $COLLECTOR_STATUS"
  echo "   Run: kubectl get pods -n agentgateway-system -l app=langfuse-otel-collector"
  exit 1
fi

# Step 2: Check tracing-params endpoint
echo ""
echo "2️⃣  Checking AgentGateway tracing endpoint..."
TRACING_ENDPOINT=$(kubectl_cmd get enterpriseagentgatewayparameters tracing -n agentgateway-system -o jsonpath='{.spec.rawConfig.config.tracing.otlpEndpoint}' 2>/dev/null || echo "NotFound")
echo "   Endpoint: $TRACING_ENDPOINT"
if echo "$TRACING_ENDPOINT" | grep -q "langfuse-otel-collector"; then
  echo "   ✅ Pointing to fan-out collector"
else
  echo "   ⚠️  Not pointing to fan-out collector (currently: $TRACING_ENDPOINT)"
  echo "   Expected: grpc://langfuse-otel-collector.agentgateway-system.svc.cluster.local:4317"
fi

# Step 3: Check collector logs for errors
echo ""
echo "3️⃣  Checking collector logs for errors..."
ERRORS=$(kubectl_cmd logs -n agentgateway-system -l app=langfuse-otel-collector --tail 50 2>/dev/null | grep -ci 'error\|fail' || true)
if [[ "$ERRORS" -eq 0 ]]; then
  echo "   ✅ No errors in collector logs"
else
  echo "   ⚠️  Found $ERRORS error(s) in collector logs"
  echo "   Run: kubectl logs -n agentgateway-system -l app=langfuse-otel-collector --tail 20"
fi

# Step 4: Send test request
echo ""
echo "4️⃣  Sending test LLM request through AgentGateway..."
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "http://${NODE_IP}:${GATEWAY_PORT}/openai/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4.1-mini","messages":[{"role":"user","content":"Langfuse verification test — respond with OK"}]}' 2>/dev/null)

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [[ "$HTTP_CODE" == "200" ]]; then
  MODEL=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('model','unknown'))" 2>/dev/null || echo "unknown")
  echo "   ✅ LLM response received (HTTP 200, model: $MODEL)"
else
  echo "   ❌ LLM request failed (HTTP $HTTP_CODE)"
  echo "   Check: curl -v http://${NODE_IP}:${GATEWAY_PORT}/openai/v1/chat/completions"
  exit 1
fi

# Step 5: Wait and check Langfuse
echo ""
echo "5️⃣  Waiting 15 seconds for trace propagation..."
sleep 15

echo "   Querying Langfuse for recent traces..."
TRACES=$(curl -s "${LANGFUSE_ENDPOINT}/api/public/traces?limit=3" \
  -H "Authorization: ${LANGFUSE_AUTH}" 2>/dev/null)

TRACE_COUNT=$(echo "$TRACES" | python3 -c "import sys,json; print(json.load(sys.stdin)['meta']['totalItems'])" 2>/dev/null || echo "0")

if [[ "$TRACE_COUNT" -gt 0 ]]; then
  echo "   ✅ Found $TRACE_COUNT trace(s) in Langfuse!"
  echo ""
  echo "   Latest trace:"
  echo "$TRACES" | python3 -c "
import sys, json
data = json.load(sys.stdin)['data'][0]
print(f\"   Name:      {data.get('name', 'N/A')}\")
print(f\"   Timestamp: {data.get('timestamp', 'N/A')}\")
print(f\"   Input:     {json.dumps(data.get('input', []), default=str)[:100]}...\")
" 2>/dev/null || true
else
  echo "   ❌ No traces found in Langfuse"
  echo "   Check collector logs: kubectl logs -n agentgateway-system -l app=langfuse-otel-collector"
fi

# Step 6: Check Solo UI (ClickHouse)
echo ""
echo "6️⃣  Checking ClickHouse (Solo Enterprise UI)..."
CH_COUNT=$(kubectl_cmd exec -n kagent kagent-mgmt-clickhouse-shard0-0 -- \
  clickhouse-client --query "SELECT count() FROM otel_traces_json WHERE Timestamp > now() - INTERVAL 5 MINUTE" 2>/dev/null || echo "0")
echo "   Traces in ClickHouse (last 5 min): $CH_COUNT"
if [[ "$CH_COUNT" -gt 0 ]]; then
  echo "   ✅ Solo Enterprise UI receiving traces"
else
  echo "   ⚠️  No recent traces in ClickHouse"
fi

echo ""
echo "============================================"
echo "  Verification Complete"
echo "============================================"
echo ""
echo "  Langfuse UI:  ${LANGFUSE_ENDPOINT}"
echo "  Solo UI:      http://${NODE_IP}:<solo-ui-port>"
echo ""
