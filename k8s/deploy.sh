#!/bin/bash

# =============================================================================
# ML Inference Infrastructure - Kubernetes Deployment Script
# =============================================================================
#
# This script deploys:
# 1. Infrastructure services via Helm (MinIO, Redis, MLflow, Grafana/Prometheus)
# 2. Inference API via Kubernetes manifests
#
# STATUS: TESTED on Docker Desktop Kubernetes (ARM64/Apple Silicon)
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="${NAMESPACE:-ml-pipeline}"
RELEASE_PREFIX="${RELEASE_PREFIX:-ml}"
IMAGE_REGISTRY="${IMAGE_REGISTRY:-}"  # Must be set for API deployment
IMAGE_TAG="${IMAGE_TAG:-1.0.0}"

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl."
        exit 1
    fi

    # Check helm
    if ! command -v helm &> /dev/null; then
        log_error "helm not found. Please install Helm 3."
        exit 1
    fi

    # Check cluster connection
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Check your kubeconfig."
        exit 1
    fi

    log_success "All prerequisites met."
}

add_helm_repos() {
    log_info "Adding Helm repositories..."

    helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
    helm repo update

    log_success "Helm repositories updated."
}

create_namespace() {
    log_info "Creating namespace: $NAMESPACE"

    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

    log_success "Namespace ready."
}

# =============================================================================
# Deployment Functions
# =============================================================================

deploy_minio() {
    log_info "Deploying MinIO..."

    helm upgrade --install "${RELEASE_PREFIX}-minio" bitnami/minio \
        --namespace "$NAMESPACE" \
        --values "$ROOT_DIR/minio/values.yaml" \
        --wait --timeout 5m

    log_success "MinIO deployed."
}

deploy_redis() {
    log_info "Deploying Redis..."

    helm upgrade --install "${RELEASE_PREFIX}-redis" bitnami/redis \
        --namespace "$NAMESPACE" \
        --values "$ROOT_DIR/redis/values.yaml" \
        --wait --timeout 5m

    log_success "Redis deployed."
}

deploy_mlflow() {
    log_info "Deploying MLflow..."

    helm upgrade --install "${RELEASE_PREFIX}-mlflow" bitnami/mlflow \
        --namespace "$NAMESPACE" \
        --values "$ROOT_DIR/mlflow/values.yaml" \
        --wait --timeout 10m

    log_success "MLflow deployed."
}

deploy_monitoring() {
    log_info "Deploying Prometheus + Grafana..."

    helm upgrade --install "${RELEASE_PREFIX}-monitoring" prometheus-community/kube-prometheus-stack \
        --namespace "$NAMESPACE" \
        --values "$ROOT_DIR/grafana/values.yaml" \
        --wait --timeout 10m

    log_success "Monitoring stack deployed."
}

deploy_api() {
    log_info "Deploying Inference API..."

    if [ -z "$IMAGE_REGISTRY" ]; then
        log_error "IMAGE_REGISTRY not set. Please set it before deploying API."
        log_info "Example: export IMAGE_REGISTRY=docker.io/yourusername"
        exit 1
    fi

    # Update kustomization with actual image
    cat > "$SCRIPT_DIR/kustomization.yaml" << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: $NAMESPACE

resources:
  - api-configmap.yaml
  - api-deployment.yaml
  - api-service.yaml
  - api-hpa.yaml
  # - api-ingress.yaml       # Uncomment if using ingress
  # - api-servicemonitor.yaml # Uncomment if using Prometheus Operator

images:
  - name: crypto-prediction-api
    newName: ${IMAGE_REGISTRY}/ml-inference-api
    newTag: "${IMAGE_TAG}"
EOF

    # Apply manifests
    kubectl apply -k "$SCRIPT_DIR"

    # Wait for deployment
    kubectl rollout status deployment/crypto-prediction-api -n "$NAMESPACE" --timeout=5m

    log_success "Inference API deployed."
}

# =============================================================================
# Status Functions
# =============================================================================

show_status() {
    log_info "Deployment Status:"
    echo ""

    echo "=== Pods ==="
    kubectl get pods -n "$NAMESPACE"
    echo ""

    echo "=== Services ==="
    kubectl get svc -n "$NAMESPACE"
    echo ""

    echo "=== HPA ==="
    kubectl get hpa -n "$NAMESPACE" 2>/dev/null || echo "No HPA found"
    echo ""
}

show_endpoints() {
    log_info "Service Endpoints (use port-forward to access):"
    echo ""
    echo "MinIO:    kubectl port-forward -n $NAMESPACE svc/${RELEASE_PREFIX}-minio 9000:9000"
    echo "MLflow:   kubectl port-forward -n $NAMESPACE svc/${RELEASE_PREFIX}-mlflow 5000:5000"
    echo "Grafana:  kubectl port-forward -n $NAMESPACE svc/${RELEASE_PREFIX}-monitoring-grafana 3000:80"
    echo "API:      kubectl port-forward -n $NAMESPACE svc/crypto-prediction-api 8000:8000"
    echo ""
}

# =============================================================================
# Cleanup Functions
# =============================================================================

cleanup() {
    log_warn "Cleaning up all deployments in namespace: $NAMESPACE"

    read -p "Are you sure? This will delete all data! (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log_info "Cleanup cancelled."
        exit 0
    fi

    log_info "Deleting Helm releases..."
    helm uninstall "${RELEASE_PREFIX}-minio" -n "$NAMESPACE" 2>/dev/null || true
    helm uninstall "${RELEASE_PREFIX}-redis" -n "$NAMESPACE" 2>/dev/null || true
    helm uninstall "${RELEASE_PREFIX}-mlflow" -n "$NAMESPACE" 2>/dev/null || true
    helm uninstall "${RELEASE_PREFIX}-monitoring" -n "$NAMESPACE" 2>/dev/null || true

    log_info "Deleting API manifests..."
    kubectl delete -k "$SCRIPT_DIR" 2>/dev/null || true

    log_info "Deleting namespace (optional)..."
    read -p "Delete namespace $NAMESPACE? (yes/no): " delete_ns
    if [ "$delete_ns" == "yes" ]; then
        kubectl delete namespace "$NAMESPACE"
    fi

    log_success "Cleanup complete."
}

# =============================================================================
# Main
# =============================================================================

usage() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  all          Deploy everything (infra + API)"
    echo "  infra        Deploy infrastructure only (MinIO, Redis, MLflow, Monitoring)"
    echo "  api          Deploy API only"
    echo "  minio        Deploy MinIO only"
    echo "  redis        Deploy Redis only"
    echo "  mlflow       Deploy MLflow only"
    echo "  monitoring   Deploy Prometheus + Grafana"
    echo "  status       Show deployment status"
    echo "  endpoints    Show service endpoints"
    echo "  cleanup      Remove all deployments"
    echo ""
    echo "Environment Variables:"
    echo "  NAMESPACE       Kubernetes namespace (default: ml-pipeline)"
    echo "  RELEASE_PREFIX  Helm release prefix (default: ml)"
    echo "  IMAGE_REGISTRY  Docker registry for API image (required for API deployment)"
    echo "  IMAGE_TAG       API image tag (default: 1.0.0)"
    echo ""
    echo "Examples:"
    echo "  $0 infra                                    # Deploy infrastructure"
    echo "  IMAGE_REGISTRY=docker.io/myuser $0 api     # Deploy API"
    echo "  $0 all                                      # Deploy everything"
    echo "  $0 status                                   # Check status"
}

main() {
    case "${1:-}" in
        all)
            check_prerequisites
            add_helm_repos
            create_namespace
            deploy_minio
            deploy_redis
            deploy_mlflow
            deploy_monitoring
            deploy_api
            show_status
            show_endpoints
            ;;
        infra)
            check_prerequisites
            add_helm_repos
            create_namespace
            deploy_minio
            deploy_redis
            deploy_mlflow
            deploy_monitoring
            show_status
            show_endpoints
            ;;
        api)
            check_prerequisites
            create_namespace
            deploy_api
            show_status
            ;;
        minio)
            check_prerequisites
            add_helm_repos
            create_namespace
            deploy_minio
            ;;
        redis)
            check_prerequisites
            add_helm_repos
            create_namespace
            deploy_redis
            ;;
        mlflow)
            check_prerequisites
            add_helm_repos
            create_namespace
            deploy_mlflow
            ;;
        monitoring)
            check_prerequisites
            add_helm_repos
            create_namespace
            deploy_monitoring
            ;;
        status)
            show_status
            ;;
        endpoints)
            show_endpoints
            ;;
        cleanup)
            cleanup
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"
