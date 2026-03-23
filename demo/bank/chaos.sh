#!/bin/bash
# kagent Bank Demo — Chaos Injection
#
# Introduces failures for kagent to diagnose live during the demo.
# Run each scenario individually or all at once.
#
# Usage:
#   ./chaos.sh crash        # Scenario 1: Java OOM crashloop
#   ./chaos.sh istio        # Scenario 4: Broken VirtualService
#   ./chaos.sh all          # Both at once
#   ./chaos.sh reset        # Restore everything to healthy

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION="${1:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
chaos() { echo -e "${RED}[CHAOS]${NC} $*"; }
prompt(){ echo -e "${CYAN}[READY]${NC} $*"; }

inject_crash() {
    chaos "Injecting Java OOM crash into payment-service..."

    # Swap the ConfigMap to the crashing version
    kubectl apply -n finance-payments -f - <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: crash-app-logs
  namespace: finance-payments
data:
  startup.sh: |
    #!/bin/sh
    echo 'INFO  2026-03-25 12:01:01 PaymentProcessor - Starting payment-service v3.2.1'
    echo 'INFO  2026-03-25 12:01:01 PaymentProcessor - Environment: dev-cluster-uk-east'
    echo 'INFO  2026-03-25 12:01:02 PaymentProcessor - Loading configuration from ConfigMap'
    echo 'INFO  2026-03-25 12:01:02 PaymentProcessor - SWIFT gateway endpoint: swift-gw.finance-payments.svc:8443'
    echo 'INFO  2026-03-25 12:01:02 DBConnectionPool - Initializing HikariCP pool (min=5, max=20)'
    echo 'INFO  2026-03-25 12:01:03 DBConnectionPool - Pool initialized successfully — 5 connections ready'
    echo 'DEBUG 2026-03-25 12:01:03 CacheManager - Warming transaction cache from Redis cluster'
    echo 'DEBUG 2026-03-25 12:01:04 CacheManager - Loading GBP settlement transactions (last 24h)'
    echo 'DEBUG 2026-03-25 12:01:04 CacheManager - Loading EUR settlement transactions (last 24h)'
    echo 'DEBUG 2026-03-25 12:01:05 CacheManager - Loading USD settlement transactions (last 24h)'
    echo 'INFO  2026-03-25 12:01:05 CacheManager - Cache warmed: 247,831 transactions loaded'
    echo 'INFO  2026-03-25 12:01:06 PaymentProcessor - Registering health check endpoint /healthz'
    echo 'INFO  2026-03-25 12:01:06 PaymentProcessor - Registering metrics endpoint /metrics'
    echo 'INFO  2026-03-25 12:01:07 PaymentProcessor - Starting gRPC server on port 9090'
    echo 'INFO  2026-03-25 12:01:07 PaymentProcessor - Starting HTTP server on port 8080'
    echo 'INFO  2026-03-25 12:01:07 PaymentProcessor - Service ready — processing payments'
    echo 'INFO  2026-03-25 12:01:08 PaymentProcessor - Processing batch settlement #BT-20260325-001'
    echo 'INFO  2026-03-25 12:01:08 PaymentProcessor - Batch contains 12,481 transactions (GBP 4.2M)'
    echo 'WARN  2026-03-25 12:01:09 CacheManager - Heap usage at 78% — approaching threshold'
    echo 'WARN  2026-03-25 12:01:09 CacheManager - GC pause detected: 1,240ms (exceeds 500ms SLA)'
    echo 'ERROR 2026-03-25 12:01:10 PaymentProcessor - Exception in thread "main" during batch settlement'
    echo 'java.lang.NullPointerException: Cannot invoke method getAmount() on null transaction reference'
    echo '    at com.bank.payments.PaymentProcessor.processPayment(PaymentProcessor.java:314)'
    echo '    at com.bank.payments.PaymentProcessor.processBatch(PaymentProcessor.java:201)'
    echo '    at com.bank.payments.PaymentProcessor.run(PaymentProcessor.java:89)'
    echo '    at java.lang.Thread.run(Thread.java:750)'
    echo 'Caused by: java.lang.OutOfMemoryError: Java heap space'
    echo '    at com.bank.payments.TransactionCache.loadAll(TransactionCache.java:201)'
    echo '    at com.bank.payments.CacheManager.warmCache(CacheManager.java:147)'
    echo '    at com.bank.payments.PaymentProcessor.initialize(PaymentProcessor.java:52)'
    echo 'FATAL 2026-03-25 12:01:10 PaymentProcessor - Service shutting down due to unrecoverable error'
    exit 1
YAML

    # Restart the pod to pick up the new ConfigMap
    kubectl rollout restart deployment/payment-service -n finance-payments
    chaos "payment-service will enter CrashLoopBackOff in ~15 seconds"
    prompt "Ask kagent: \"There's a pod crash-looping in the finance-payments namespace. Can you diagnose what's going wrong and tell me the root cause?\""
}

inject_istio() {
    chaos "Breaking Istio VirtualService — routing to non-existent service..."

    kubectl apply -n finance-payments -f - <<'YAML'
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: payment-vs
  namespace: finance-payments
spec:
  hosts:
  - payment-service
  http:
  - route:
    - destination:
        host: payment-svc-v2
        port:
          number: 8080
YAML

    chaos "payment-vs now routes to payment-svc-v2 (does not exist)"
    prompt "Ask kagent: \"The payment-service in finance-payments isn't receiving any traffic through the mesh. Can you check the Istio configuration and find what's wrong?\""
}

reset_all() {
    info "Restoring healthy state..."

    # Restore healthy ConfigMap + restart
    kubectl apply -f "$SCRIPT_DIR/crashloop-pod.yaml"
    kubectl rollout restart deployment/payment-service -n finance-payments

    # Restore correct VirtualService
    kubectl apply -f "$SCRIPT_DIR/istio-virtualservice.yaml" 2>/dev/null || true

    info "All workloads restored to healthy state"
}

case "${ACTION}" in
    crash)
        inject_crash
        ;;
    istio)
        inject_istio
        ;;
    all)
        inject_crash
        echo ""
        inject_istio
        ;;
    reset|restore|fix)
        reset_all
        ;;
    *)
        echo "Usage: $0 {crash|istio|all|reset}"
        echo ""
        echo "  crash   Inject Java OOM crashloop into payment-service"
        echo "  istio   Break VirtualService routing to non-existent service"
        echo "  all     Inject all chaos at once"
        echo "  reset   Restore everything to healthy"
        exit 1
        ;;
esac
