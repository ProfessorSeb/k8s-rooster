#!/bin/bash
# kagent Bank Demo — Chaos Injection
#
# Introduces failures for kagent to diagnose live during the demo.
# Run each scenario individually or all at once.
#
# Usage:
#   ./chaos.sh crash        # Scenario 1: Java OOM crashloop
#   ./chaos.sh istio        # Scenario 4: Broken VirtualService
#   ./chaos.sh khook        # Scenario 6: Break compliance-report-generator (khook auto-responds)
#   ./chaos.sh mesh         # Scenario 7: Break ambient mesh — STRICT mTLS + deny-all AuthorizationPolicy
#   ./chaos.sh all          # All chaos at once
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

inject_khook() {
    chaos "Injecting database connection failure into compliance-report-generator..."

    # Swap ConfigMap to the crashing version — DB connection timeout
    kubectl apply -n compliance-ops -f - <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: compliance-report-config
  namespace: compliance-ops
data:
  startup.sh: |
    #!/bin/sh
    echo 'INFO  2026-03-23 09:00:01 ReportGenerator - Compliance Report Generator v2.1.0 starting'
    echo 'INFO  2026-03-23 09:00:01 ReportGenerator - Environment: prod-cluster-uk-east'
    echo 'INFO  2026-03-23 09:00:02 HikariPool - Initializing connection pool (min=2, max=10)'
    echo 'WARN  2026-03-23 09:00:32 HikariPool - Connection attempt 1/3 timed out after 30000ms'
    echo 'WARN  2026-03-23 09:01:02 HikariPool - Connection attempt 2/3 timed out after 30000ms'
    echo 'ERROR 2026-03-23 09:01:32 HikariPool - Connection attempt 3/3 failed — pool exhausted'
    echo 'ERROR 2026-03-23 09:01:32 ReportGenerator - Failed to connect to regulatory-db.compliance-ops.svc:5432'
    echo 'java.sql.SQLTransientConnectionException: HikariPool-1 - Connection not available, request timed out after 30000ms'
    echo '    at com.zaxxer.hikari.pool.HikariPool.createTimeoutException(HikariPool.java:696)'
    echo '    at com.zaxxer.hikari.pool.HikariPool.getConnection(HikariPool.java:197)'
    echo '    at com.bank.compliance.db.RegulationDAO.query(RegulationDAO.java:84)'
    echo '    at com.bank.compliance.ReportGenerator.loadDataset(ReportGenerator.java:187)'
    echo '    at com.bank.compliance.ReportGenerator.init(ReportGenerator.java:63)'
    echo '    at java.lang.Thread.run(Thread.java:750)'
    echo 'Caused by: org.postgresql.util.PSQLException: Connection to regulatory-db.compliance-ops.svc:5432 refused'
    echo '    at org.postgresql.core.v3.ConnectionFactoryImpl.openConnectionImpl(ConnectionFactoryImpl.java:319)'
    echo '    at org.postgresql.core.ConnectionFactory.openConnection(ConnectionFactory.java:49)'
    echo '    at org.postgresql.jdbc.PgConnection.<init>(PgConnection.java:247)'
    echo 'FATAL 2026-03-23 09:01:32 ReportGenerator - Cannot generate compliance reports without database access'
    echo 'FATAL 2026-03-23 09:01:32 ReportGenerator - Shutting down — MiFID II reporting SLA at risk'
    exit 1
YAML

    # Restart to pick up broken ConfigMap
    kubectl rollout restart deployment/compliance-report-generator -n compliance-ops
    chaos "compliance-report-generator will enter CrashLoopBackOff in ~15 seconds"
    chaos "khook will auto-detect the pod-restart event and trigger bank-platform-agent"
    prompt "Watch the kagent UI — the agent will start diagnosing automatically (no human prompt needed)"
}

inject_mesh() {
    chaos "Breaking ambient mesh — injecting STRICT mTLS + deny-all AuthorizationPolicy..."

    # PeerAuthentication: force STRICT mTLS — breaks any non-mesh client
    kubectl apply -n finance-payments -f - <<'YAML'
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: chaos-strict-mtls
  namespace: finance-payments
spec:
  mtls:
    mode: STRICT
YAML

    # AuthorizationPolicy: deny all traffic to payment-service
    kubectl apply -n finance-payments -f - <<'YAML'
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: chaos-deny-all
  namespace: finance-payments
spec:
  selector:
    matchLabels:
      app: payment-service
  action: DENY
  rules:
  - from:
    - source:
        namespaces: ["*"]
YAML

    chaos "payment-service is now unreachable — STRICT mTLS + DENY policy active"
    prompt "Ask kagent: \"The payment-service in finance-payments is rejecting all connections. Can you check the Istio security policies and figure out what's blocking traffic?\""
}

test_connectivity() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Mesh Connectivity Test — payment-service:8080${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Check for blocking policies
    local strict_mtls deny_policy
    strict_mtls=$(kubectl get peerauthentication -n finance-payments chaos-strict-mtls -o name 2>/dev/null || true)
    deny_policy=$(kubectl get authorizationpolicy -n finance-payments chaos-deny-all -o name 2>/dev/null || true)

    if [[ -n "$strict_mtls" || -n "$deny_policy" ]]; then
        echo -e "  ${RED}■${NC} Blocking policies detected:"
        [[ -n "$strict_mtls" ]] && echo -e "    ${RED}✗${NC} PeerAuthentication/chaos-strict-mtls  ${RED}STRICT mTLS${NC}"
        [[ -n "$deny_policy" ]] && echo -e "    ${RED}✗${NC} AuthorizationPolicy/chaos-deny-all    ${RED}DENY ALL${NC}"
        echo ""
    else
        echo -e "  ${GREEN}■${NC} No blocking policies found"
        echo ""
    fi

    # Test HTTP from inside the existing payment-service pod (busybox has wget)
    echo -e "  Testing from payment-service pod via wget..."
    echo ""

    local result exit_code
    result=$(kubectl exec -n finance-payments deployment/payment-service -- \
        wget -q -O - --timeout=3 http://payment-service.finance-payments.svc:8080/ 2>&1)
    exit_code=$?

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    if [[ "$exit_code" -eq 0 ]]; then
        echo -e "  ${GREEN}████████████████████████████████████████████${NC}"
        echo -e "  ${GREEN}█                                          █${NC}"
        echo -e "  ${GREEN}█      ✓  CONNECTION SUCCESSFUL            █${NC}"
        echo -e "  ${GREEN}█                                          █${NC}"
        echo -e "  ${GREEN}████████████████████████████████████████████${NC}"
        echo ""
        echo -e "  Response: ${GREEN}${result}${NC}"
    else
        echo -e "  ${RED}████████████████████████████████████████████${NC}"
        echo -e "  ${RED}█                                          █${NC}"
        echo -e "  ${RED}█      ✗  CONNECTION FAILED                █${NC}"
        echo -e "  ${RED}█         Traffic blocked by mesh policy   █${NC}"
        echo -e "  ${RED}█                                          █${NC}"
        echo -e "  ${RED}████████████████████████████████████████████${NC}"
        echo ""
        echo -e "  Error: ${RED}${result}${NC}"
    fi
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${CYAN}Kiali UI:${NC} http://172.16.20.127:20001"
    echo ""
}

reset_all() {
    info "Restoring healthy state..."

    # Restore healthy ConfigMap + restart
    kubectl apply -f "$SCRIPT_DIR/crashloop-pod.yaml"
    kubectl rollout restart deployment/payment-service -n finance-payments

    # Restore correct VirtualService
    kubectl apply -f "$SCRIPT_DIR/istio-virtualservice.yaml" 2>/dev/null || true

    # Restore healthy compliance-report-generator
    kubectl apply -f "$SCRIPT_DIR/khook-workload.yaml"
    kubectl rollout restart deployment/compliance-report-generator -n compliance-ops

    # Remove mesh chaos policies
    kubectl delete peerauthentication chaos-strict-mtls -n finance-payments 2>/dev/null || true
    kubectl delete authorizationpolicy chaos-deny-all -n finance-payments 2>/dev/null || true

    info "All workloads restored to healthy state"
}

case "${ACTION}" in
    crash)
        inject_crash
        ;;
    istio)
        inject_istio
        ;;
    khook)
        inject_khook
        ;;
    mesh)
        inject_mesh
        ;;
    test)
        test_connectivity
        ;;
    all)
        inject_crash
        echo ""
        inject_istio
        echo ""
        inject_khook
        echo ""
        inject_mesh
        ;;
    reset|restore|fix)
        reset_all
        ;;
    *)
        echo "Usage: $0 {crash|istio|khook|mesh|all|reset|test}"
        echo ""
        echo "  crash   Inject Java OOM crashloop into payment-service"
        echo "  istio   Break VirtualService routing to non-existent service"
        echo "  khook   Break compliance-report-generator (khook auto-responds)"
        echo "  mesh    Break ambient mesh — STRICT mTLS + deny-all policy"
        echo "  all     Inject all chaos at once"
        echo "  reset   Restore everything to healthy"
        echo "  test    Test connectivity to payment-service (visual pass/fail)"
        exit 1
        ;;
esac
