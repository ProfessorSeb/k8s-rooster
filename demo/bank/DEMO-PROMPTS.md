# kagent Bank Demo — Prompts Cheat Sheet

> Use the **bank-platform-agent** in kagent UI for all scenarios.

---

## Setup (30 min before)

```bash
./setup.sh apply     # Everything deploys HEALTHY
./setup.sh status    # Verify all green
```

---

## Scenario 1 — Crash Loop Diagnosis (3 min) — THE HOOK

**Inject chaos:**
```bash
./chaos.sh crash
```
Wait ~15 seconds for CrashLoopBackOff, then ask kagent:

**Prompt:**
```
There's a pod crash-looping in the finance-payments namespace. Can you diagnose what's going wrong and tell me the root cause?
```

**What kagent does:** describe pod → events → logs → finds NullPointerException + OOM at PaymentProcessor.java:314

**Follow-up (if time):**
```
What would you recommend to fix the OutOfMemoryError? Should we increase the heap or is the caching strategy the real problem?
```

---

## Scenario 2 — Migration Candidate Identification (3 min)

> No chaos needed — this uses the healthy workloads

**Prompt:**
```
We're planning a workload migration to a new cluster. Which workloads across all namespaces are stateless and would be safe to migrate first?
```

**Expected:** kagent queries PVCs, correlates with pods, identifies risk-api and compliance-batch as stateless. Flags market-data-store as stateful.

**Follow-up:**
```
For risk-api specifically, what dependencies or risks should we be aware of before migrating it?
```

---

## Scenario 3 — Cluster Capacity Forecasting (2 min)

> No chaos needed — requires Prometheus + kube-state-metrics

**Prompt:**
```
Based on current resource consumption trends, when will this cluster run out of allocatable CPU or memory?
```

**What kagent does:** Queries Prometheus via the prometheus-mcp tool, analyses node metrics, projects fill date.

---

## Scenario 4 — Istio Troubleshooting (3 min)

**Inject chaos:**
```bash
./chaos.sh istio
```
Then ask kagent:

**Prompt:**
```
The payment-service in finance-payments isn't receiving any traffic through the mesh. Can you check the Istio configuration and find what's wrong?
```

**Expected:** Checks VirtualServices, DestinationRules, Services. Finds payment-vs routes to payment-svc-v2 which doesn't exist as a k8s Service.

---

## Scenario 5 — Namespace Migration (3 min)

> Use the **k8s-agent** for this scenario

**Setup:**
```bash
./chaos.sh migrate
```
This deploys `fruit-app` (Deployment + Service + ConfigMap) in namespace `apples`. Namespace `oranges` is empty.

**Prompt:**
```
Migrate the fruit-app and all its resources from namespace apples to namespace oranges. Make sure it's running in oranges, then clean up apples.
```

**What kagent does:** Gets resources in apples → exports YAML for Deployment, Service, ConfigMap → applies them in oranges → verifies pods are running → deletes resources in apples

**Follow-up (if time):**
```
Can you verify the fruit-app is healthy in the oranges namespace and the apples namespace is fully cleaned up?
```

---

## Scenario 6 — Extensibility Teaser (2 min)

> Narrate while showing kagent agent config screen. No live demo needed.

**Talking points:**
- "kagent supports custom MCP tool servers — we can wire any internal API"
- "Imagine adding your internal migration API as a tool"
- "Agent identifies candidate → human approves → API executes migration"
- "Same pattern works for Ansible Tower, ServiceNow, or any REST API"

---

## Quick Reference

| Command | What it does |
|---------|-------------|
| `./setup.sh apply` | Deploy everything healthy |
| `./setup.sh status` | Check all pods/agents/tools |
| `./chaos.sh crash` | Break payment-service (Java OOM) |
| `./chaos.sh istio` | Break VirtualService routing |
| `./chaos.sh migrate` | Set up namespace migration (fruit-app: apples → oranges) |
| `./chaos.sh all` | All chaos at once |
| `./chaos.sh reset` | Restore healthy state |
| `./setup.sh delete` | Tear down everything |

---

## Pre-Demo Checklist

- [ ] `./setup.sh apply` — deploy everything healthy
- [ ] `./setup.sh status` — all pods Running, agent registered
- [ ] bank-platform-agent shows in kagent UI
- [ ] prometheus-mcp-server pod Running in kagent namespace
- [ ] kagent UI accessible and responsive
- [ ] Dry-run: `./chaos.sh crash` → test Scenario 1 prompt → `./chaos.sh reset`
- [ ] Observability dashboard shows agent traces
- [ ] Close unnecessary browser tabs / notifications
