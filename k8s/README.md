# Kubernetes Deployment Manifests

This directory contains Kubernetes manifests for deploying the Crypto ML Pipeline production API.

## Files Overview

| File | Description |
|------|-------------|
| `secrets.yaml.example` | Template for Kubernetes secrets (passwords, API keys) |
| `api-configmap.yaml` | Non-sensitive configuration (hostnames, ports, etc.) |
| `api-deployment.yaml` | Main application deployment with 2 replicas |
| `api-service.yaml` | ClusterIP service exposing port 8000 |
| `api-hpa.yaml` | Horizontal Pod Autoscaler (2-10 replicas) |
| `api-ingress.yaml` | Ingress for external access (optional) |
| `api-servicemonitor.yaml` | Prometheus ServiceMonitor for metrics |
| `kustomization.yaml` | Kustomize configuration for easier deployment |

## Prerequisites

1. Kubernetes cluster (v1.20+)
2. kubectl configured and connected to your cluster
3. Namespace created: `kubectl create namespace ml-pipeline`
4. Docker image built and pushed to registry
5. Prometheus Operator installed (for ServiceMonitor)
6. Ingress Controller installed (for Ingress, e.g., nginx-ingress)

## Quick Start

### 1. Create Secrets

First, create your secrets from the template:

```bash
# Copy the example
cp secrets.yaml.example secrets.yaml

# Edit and fill in actual values (base64 encoded)
nano secrets.yaml

# Encode secrets (example)
echo -n "your_db_password" | base64
echo -n "your_minio_key" | base64

# Apply secrets
kubectl apply -f secrets.yaml
```

### 2. Review and Update ConfigMap

Edit `api-configmap.yaml` to match your environment:

```bash
nano api-configmap.yaml

# Update these values:
# - DB_HOST
# - MINIO_ENDPOINT
# - REDIS_HOST
# - MLFLOW_TRACKING_URI
# - BINANCE_SYMBOLS (your trading pairs)
```

### 3. Update Docker Image

Edit `api-deployment.yaml` or `kustomization.yaml`:

```yaml
# In api-deployment.yaml, update:
image: your-registry.com/crypto-prediction-api:1.0.0

# OR in kustomization.yaml:
images:
  - name: crypto-prediction-api
    newName: your-registry.com/crypto-prediction-api
    newTag: "1.0.0"
```

### 4. Deploy Using kubectl

```bash
# Apply manifests in order
kubectl apply -f api-configmap.yaml
kubectl apply -f secrets.yaml
kubectl apply -f api-deployment.yaml
kubectl apply -f api-service.yaml
kubectl apply -f api-hpa.yaml
kubectl apply -f api-ingress.yaml        # Optional
kubectl apply -f api-servicemonitor.yaml # Optional

# Or apply all at once
kubectl apply -f .
```

### 5. Deploy Using Kustomize

```bash
# Build and preview
kubectl kustomize .

# Apply with kustomize
kubectl apply -k .
```

## Verification

### Check Deployment Status

```bash
# Check pods
kubectl get pods -n ml-pipeline -l app=crypto-prediction-api

# Check deployment
kubectl describe deployment crypto-prediction-api -n ml-pipeline

# Check service
kubectl get svc crypto-prediction-api -n ml-pipeline

# Check HPA
kubectl get hpa -n ml-pipeline

# View logs
kubectl logs -f deployment/crypto-prediction-api -n ml-pipeline
```

### Test the API

```bash
# Port forward for local testing
kubectl port-forward svc/crypto-prediction-api 8000:8000 -n ml-pipeline

# Test health endpoint
curl http://localhost:8000/health

# Test prediction endpoint
curl http://localhost:8000/predict/BTCUSDT

# View API docs
open http://localhost:8000/docs
```

### Monitor

```bash
# Check metrics endpoint
kubectl port-forward svc/crypto-prediction-api 8000:8000 -n ml-pipeline
curl http://localhost:8000/metrics

# View Prometheus targets (if ServiceMonitor is working)
# Access Prometheus UI and check Targets page
```

## Configuration

### Resource Limits

Current configuration (per pod):

- CPU Request: 500m (0.5 cores)
- CPU Limit: 2000m (2 cores)
- Memory Request: 1Gi
- Memory Limit: 4Gi

Adjust in `api-deployment.yaml` based on your needs.

### Auto-scaling

HPA is configured to scale between 2-10 replicas based on:
- CPU: 70% average utilization
- Memory: 80% average utilization

Modify `api-hpa.yaml` to change thresholds.

### Health Checks

Three types of probes are configured:

1. **Liveness Probe**: Restarts container if unhealthy
   - Endpoint: `/health`
   - Initial delay: 30s
   - Period: 10s

2. **Readiness Probe**: Removes from service if not ready
   - Endpoint: `/health`
   - Initial delay: 10s
   - Period: 5s

3. **Startup Probe**: Allows longer startup time
   - Endpoint: `/health`
   - Failure threshold: 30 (5 minutes max)

## Troubleshooting

### Pods Not Starting

```bash
# Check pod events
kubectl describe pod <pod-name> -n ml-pipeline

# Check logs
kubectl logs <pod-name> -n ml-pipeline

# Common issues:
# - Image pull errors: Check image name and registry credentials
# - Configuration errors: Verify ConfigMap and Secrets
# - Resource constraints: Check node resources
```

### Pods Crashing

```bash
# View crash logs
kubectl logs <pod-name> -n ml-pipeline --previous

# Check if health checks are too aggressive
# Increase initialDelaySeconds in api-deployment.yaml
```

### HPA Not Scaling

```bash
# Check metrics server is installed
kubectl get apiservice v1beta1.metrics.k8s.io

# Check HPA status
kubectl describe hpa crypto-prediction-api-hpa -n ml-pipeline

# Install metrics-server if missing:
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### Ingress Not Working

```bash
# Check ingress status
kubectl describe ingress crypto-prediction-api-ingress -n ml-pipeline

# Check ingress controller logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller

# Verify DNS points to ingress IP
kubectl get ingress -n ml-pipeline
```

## Updating

### Rolling Update

```bash
# Update image tag in deployment
kubectl set image deployment/crypto-prediction-api \
  api=your-registry.com/crypto-prediction-api:1.1.0 \
  -n ml-pipeline

# Or edit deployment
kubectl edit deployment crypto-prediction-api -n ml-pipeline

# Watch rollout
kubectl rollout status deployment/crypto-prediction-api -n ml-pipeline
```

### Rollback

```bash
# View rollout history
kubectl rollout history deployment/crypto-prediction-api -n ml-pipeline

# Rollback to previous version
kubectl rollout undo deployment/crypto-prediction-api -n ml-pipeline

# Rollback to specific revision
kubectl rollout undo deployment/crypto-prediction-api --to-revision=2 -n ml-pipeline
```

### Update ConfigMap

```bash
# Edit configmap
kubectl edit configmap ml-pipeline-config -n ml-pipeline

# Restart pods to pick up changes
kubectl rollout restart deployment/crypto-prediction-api -n ml-pipeline
```

## Cleanup

```bash
# Delete all resources
kubectl delete -f .

# Or with kustomize
kubectl delete -k .

# Delete namespace (WARNING: deletes everything)
kubectl delete namespace ml-pipeline
```

## Production Checklist

Before deploying to production:

- [ ] Update all placeholder values in ConfigMap
- [ ] Create and apply Secrets with real credentials
- [ ] Update Docker image reference to your registry
- [ ] Configure proper DNS for Ingress hostname
- [ ] Set up TLS certificates (update Ingress)
- [ ] Configure resource limits based on load testing
- [ ] Set up monitoring and alerting
- [ ] Test health check endpoints
- [ ] Verify backup and disaster recovery procedures
- [ ] Document runbooks for common issues
- [ ] Set up log aggregation (ELK, Loki, etc.)
- [ ] Configure network policies for security
- [ ] Set up pod disruption budgets for high availability

## Security Considerations

1. **Secrets Management**:
   - Never commit `secrets.yaml` to git
   - Consider using external secret managers (Vault, AWS Secrets Manager, etc.)
   - Rotate secrets regularly

2. **Network Security**:
   - Use NetworkPolicies to restrict pod communication
   - Enable TLS for all external endpoints
   - Limit ingress to specific IPs if possible

3. **RBAC**:
   - Create service accounts with minimal permissions
   - Use Pod Security Policies or Pod Security Standards
   - Audit access regularly

4. **Image Security**:
   - Scan images for vulnerabilities
   - Use specific tags, not `:latest`
   - Pull from trusted registries only

## Support

For issues or questions:
- Check application logs: `kubectl logs -f deployment/crypto-prediction-api -n ml-pipeline`
- Review pod events: `kubectl describe pod <pod-name> -n ml-pipeline`
- Check this README and NEXT_STEPS.md in the project root
