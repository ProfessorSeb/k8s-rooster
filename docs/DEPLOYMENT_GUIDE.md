# Deployment Guide

## Overview

This guide provides step-by-step instructions for deploying the Longhorn storage system and AgentGateway in a Kubernetes environment using ArgoCD.

## Pre-Deployment Checklist

### Cluster Requirements

- [ ] Kubernetes cluster version 1.20 or higher
- [ ] At least 3 worker nodes for Longhorn high availability
- [ ] Sufficient storage space on worker nodes (minimum 10GB per node)
- [ ] iscsi-initiator-utils installed on all worker nodes
- [ ] ArgoCD installed and accessible

### Required Tools

- [ ] `kubectl` configured with cluster access
- [ ] `helm` (optional, for manual deployments)
- [ ] Base64 encoding tool for secrets

### Prerequisites Validation

```bash
# Check cluster version
kubectl version --short

# Verify node readiness
kubectl get nodes

# Check available storage
kubectl describe nodes | grep -A 5 "Allocatable"

# Validate ArgoCD installation
kubectl get pods -n argocd
```

## Deployment Sequence

### Phase 1: ArgoCD Setup (if not installed)

1. **Install ArgoCD**:
   ```bash
   kubectl create namespace argocd
   kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
   ```

2. **Configure Access**:
   ```bash
   kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort"}}'
   ```

3. **Get Admin Password**:
   ```bash
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
   ```

4. **Set Security Context**:
   ```bash
   kubectl label namespace argocd pod-security.kubernetes.io/enforce=privileged \
     pod-security.kubernetes.io/audit=privileged \
     pod-security.kubernetes.io/warn=privileged --overwrite
   ```

### Phase 2: Longhorn Storage Deployment

1. **Deploy Longhorn System**:
   ```bash
   kubectl apply -f manifests/longhorn/longhorn.yaml
   ```

2. **Verify Deployment**:
   ```bash
   # Wait for all pods to be ready (this may take 5-10 minutes)
   kubectl get pods -n longhorn-system -w
   
   # Check storage class creation
   kubectl get storageclass longhorn
   
   # Verify Longhorn manager
   kubectl get daemonset -n longhorn-system
   ```

3. **Test Storage Functionality**:
   ```bash
   # Create a test PVC
   kubectl apply -f - <<EOF
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: longhorn-test-pvc
     namespace: default
   spec:
     accessModes:
       - ReadWriteOnce
     storageClassName: longhorn
     resources:
       requests:
         storage: 1Gi
   EOF
   
   # Verify PVC binding
   kubectl get pvc longhorn-test-pvc
   
   # Cleanup test
   kubectl delete pvc longhorn-test-pvc
   ```

### Phase 3: AgentGateway Deployment

1. **Create License Secret**:
   ```bash
   # Replace with your actual license key
   export AGENTGATEWAY_LICENSE_KEY="your-enterprise-license-key"
   
   kubectl create namespace agentgateway-system
   kubectl create secret generic agent-gateway-license \
     -n agentgateway-system \
     --from-literal=license-key="$AGENTGATEWAY_LICENSE_KEY"
   ```

2. **Deploy CRDs First**:
   ```bash
   kubectl apply -f manifests/agentgateway/agentgateway-crds-application.yaml
   ```

3. **Wait for CRDs to be Ready**:
   ```bash
   # Check ArgoCD application status
   kubectl get application enterprise-agentgateway-crds-helm -n argocd
   
   # Verify CRDs are installed
   kubectl get crd | grep -E "(gateway|gloo)"
   ```

4. **Deploy Main Application**:
   ```bash
   kubectl apply -f manifests/agentgateway/agentgateway-main-application.yaml
   ```

5. **Monitor Deployment**:
   ```bash
   # Watch pods coming up
   kubectl get pods -n agentgateway-system -w
   
   # Check ArgoCD applications
   kubectl get applications -n argocd
   
   # Verify services
   kubectl get svc -n agentgateway-system
   ```

## Post-Deployment Validation

### Longhorn Validation

```bash
# Check all Longhorn components
kubectl get all -n longhorn-system

# Verify storage class is default
kubectl get storageclass

# Check Longhorn settings
kubectl get settings -n longhorn-system

# Access Longhorn UI (if service is exposed)
kubectl get svc longhorn-frontend -n longhorn-system
```

### AgentGateway Validation

```bash
# Verify all pods are running
kubectl get pods -n agentgateway-system

# Check gateway configurations
kubectl get gateways -A

# Verify virtual services
kubectl get virtualservices -A

# Check ArgoCD sync status
kubectl describe application enterprise-agentgateway-helm -n argocd
```

## Rollback Procedures

### Longhorn Rollback

```bash
# Scale down Longhorn components
kubectl scale deployment longhorn-ui --replicas=0 -n longhorn-system
kubectl scale deployment longhorn-driver-deployer --replicas=0 -n longhorn-system

# Delete Longhorn (WARNING: This will remove all data)
kubectl delete -f manifests/longhorn/longhorn.yaml
```

### AgentGateway Rollback

```bash
# Delete ArgoCD applications
kubectl delete application enterprise-agentgateway-helm -n argocd
kubectl delete application enterprise-agentgateway-crds-helm -n argocd

# Manual cleanup if needed
kubectl delete namespace agentgateway-system
```

## Configuration Management

### Backup Current State

```bash
# Create backup directory
mkdir -p backups/$(date +%Y-%m-%d)

# Backup Longhorn configuration
kubectl get all,configmap,secret -n longhorn-system -o yaml > backups/$(date +%Y-%m-%d)/longhorn-backup.yaml

# Backup AgentGateway configuration
kubectl get all,configmap,secret -n agentgateway-system -o yaml > backups/$(date +%Y-%m-%d)/agentgateway-backup.yaml
```

### Update Procedures

1. **Test in Development**: Always test configuration changes in a development environment first.

2. **Use ArgoCD**: For AgentGateway updates, modify the ArgoCD application specifications.

3. **Version Control**: All changes should be committed to git with descriptive commit messages.

4. **Gradual Rollouts**: For production environments, consider blue-green or canary deployments.

## Troubleshooting Common Issues

### Longhorn Issues

**Pods stuck in Pending state:**
```bash
# Check node requirements
kubectl describe node <node-name> | grep -A 10 "Conditions"

# Verify storage availability
df -h /var/lib/longhorn/
```

**Volume mounting failures:**
```bash
# Check Longhorn events
kubectl get events -n longhorn-system --sort-by='.lastTimestamp'

# Verify CSI driver
kubectl get pods -n longhorn-system | grep csi
```

### AgentGateway Issues

**License errors:**
```bash
# Verify license secret
kubectl get secret agent-gateway-license -n agentgateway-system -o yaml

# Check pod logs for license validation
kubectl logs -l app.kubernetes.io/name=gloo -n agentgateway-system
```

**ArgoCD sync failures:**
```bash
# Check ArgoCD application status
kubectl describe application enterprise-agentgateway-helm -n argocd

# Force refresh and sync
kubectl patch application enterprise-agentgateway-helm -n argocd \
  --type merge -p '{"operation":{"sync":{"syncStrategy":{"hook":{"force":true}}}}}'
```

## Monitoring and Alerts

### Key Metrics to Monitor

- **Longhorn**: Volume health, storage utilization, replica status
- **AgentGateway**: Gateway availability, request latency, error rates
- **Kubernetes**: Pod status, resource utilization, events

### Recommended Monitoring Stack

- Prometheus + Grafana for metrics
- ELK stack or similar for log aggregation
- AlertManager for notifications

---

For additional support, refer to the main README.md or contact the platform team.