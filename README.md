# Kubernetes Environment - Rooster

This repository contains Kubernetes configurations for deploying Longhorn storage and AgentGateway systems in a production environment.

## Repository Structure

```
k8s-rooster/
├── manifests/              # Original deployment manifests
│   ├── longhorn/           # Longhorn deployment files
│   └── agentgateway/       # AgentGateway ArgoCD applications
├── configs/                # Current running configurations (extracted)
│   ├── longhorn/           # Longhorn system current state
│   └── agentgateway/       # AgentGateway system current state
├── docs/                   # Additional documentation
└── README.md              # This file
```

## Prerequisites

- Kubernetes cluster (1.20+)
- ArgoCD installed and configured
- kubectl configured to access your cluster
- Appropriate node resources and storage for Longhorn

## Quick Start

### 1. Setup ArgoCD (if not already installed)

```bash
# Create ArgoCD namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Configure ArgoCD server access (NodePort)
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort"}}'

# Get ArgoCD initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Set security labels for ArgoCD namespace
kubectl label namespace argocd pod-security.kubernetes.io/enforce=privileged pod-security.kubernetes.io/audit=privileged pod-security.kubernetes.io/warn=privileged --overwrite
```

### 2. Deploy Longhorn Storage System

Longhorn provides distributed block storage for Kubernetes.

```bash
# Option 1: Direct deployment
kubectl apply -f manifests/longhorn/longhorn.yaml

# Option 2: Using the current running config (cleaned)
kubectl apply -f configs/longhorn/
```

**Post-deployment verification:**
```bash
# Check Longhorn system status
kubectl get pods -n longhorn-system

# Verify storage class
kubectl get storageclass

# Access Longhorn UI (if exposed)
kubectl get svc -n longhorn-system
```

### 3. Deploy AgentGateway System

AgentGateway requires a license key for Enterprise features.

```bash
# Create AgentGateway license secret (REQUIRED)
export AGENTGATEWAY_LICENSE_KEY="your-license-key-here"
kubectl create secret generic agent-gateway-license -n agentgateway-system --from-literal=license-key="$AGENTGATEWAY_LICENSE_KEY"

# Deploy AgentGateway CRDs first
kubectl apply -f manifests/agentgateway/agentgateway-crds-application.yaml

# Deploy AgentGateway main application
kubectl apply -f manifests/agentgateway/agentgateway-main-application.yaml
```

**Post-deployment verification:**
```bash
# Check AgentGateway system status
kubectl get pods -n agentgateway-system

# Verify ArgoCD applications
kubectl get applications -n argocd
```

## Configuration Details

### Longhorn Configuration

- **Version**: v1.6.2
- **Default Storage Class**: `longhorn` (set as default)
- **Replica Count**: 3
- **Namespace**: `longhorn-system`

**Key Features Enabled:**
- Automatic storage provisioning
- Volume expansion support
- Priority class for high availability
- CSI driver integration

### AgentGateway Configuration

- **Chart Version**: 2.1.0
- **Repository**: `us-docker.pkg.dev/solo-public/enterprise-agentgateway/charts`
- **Namespace**: `agentgateway-system`

**Deployment Strategy:**
- Automated sync with ArgoCD
- Self-healing enabled
- Server-side apply for large resources
- License-based Enterprise features

## Current Running Configurations

The `configs/` directory contains cleaned configurations extracted from the running cluster:

- **deployments.yaml**: Application deployments
- **services.yaml**: Service definitions
- **configmaps.yaml**: Configuration maps (sensitive data redacted)
- **serviceaccounts.yaml**: Service accounts (secrets removed)
- **daemonsets.yaml**: DaemonSet configurations
- **crds.yaml**: Custom Resource Definitions

These configurations represent the actual running state and can be used for:
- Backup and disaster recovery
- Environment replication
- Configuration drift detection
- Troubleshooting and debugging

## Security Considerations

### Sensitive Data Handling

- All sensitive data (secrets, tokens, license keys) has been redacted from configs
- License keys must be created separately using kubectl
- Service account tokens are excluded from exported configurations

### Required Secrets

1. **AgentGateway License**: Required for Enterprise features
   ```bash
   kubectl create secret generic agent-gateway-license \
     -n agentgateway-system \
     --from-literal=license-key="YOUR_LICENSE_KEY"
   ```

## Monitoring and Maintenance

### Health Checks

```bash
# Check all system pods
kubectl get pods -n longhorn-system
kubectl get pods -n agentgateway-system

# Verify storage functionality
kubectl get pv,pvc --all-namespaces

# Check ArgoCD sync status
kubectl get applications -n argocd
```

### Common Operations

**Scale Longhorn replicas:**
```bash
kubectl patch storageclass longhorn -p '{"parameters":{"numberOfReplicas":"2"}}'
```

**Update AgentGateway version:**
Edit `manifests/agentgateway/agentgateway-main-application.yaml` and update `targetRevision`.

**Backup configurations:**
```bash
# Export current configurations
kubectl get all,configmap,pv,pvc -n longhorn-system -o yaml > longhorn-backup.yaml
kubectl get all,configmap,pv,pvc -n agentgateway-system -o yaml > agentgateway-backup.yaml
```

## Troubleshooting

### Common Issues

1. **Longhorn volumes not mounting**:
   - Check node storage requirements
   - Verify iscsi-initiator-utils installed on nodes
   - Check node selectors and taints

2. **AgentGateway license errors**:
   - Verify license secret exists and is valid
   - Check secret name matches configuration
   - Ensure license has not expired

3. **ArgoCD sync failures**:
   - Check repository access
   - Verify Helm chart versions
   - Review ArgoCD server logs

### Useful Commands

```bash
# Describe problematic pods
kubectl describe pod <pod-name> -n <namespace>

# Check logs
kubectl logs <pod-name> -n <namespace>

# Force ArgoCD sync
kubectl patch application <app-name> -n argocd -p '{"operation":{"sync":{"syncStrategy":{"hook":{"force":true}}}}}'
```

## Contributing

When updating configurations:

1. Extract current state: `kubectl get <resource> -n <namespace> -o yaml`
2. Clean sensitive data using provided scripts
3. Test in development environment
4. Update documentation
5. Commit changes with descriptive messages

## Support

For issues related to:
- **Longhorn**: [Longhorn Documentation](https://longhorn.io/docs/)
- **AgentGateway**: Contact Solo.io support
- **ArgoCD**: [ArgoCD Documentation](https://argo-cd.readthedocs.io/)

---

**Last Updated**: February 8, 2026
**Cluster**: Production Environment
**Maintainer**: DevOps Team