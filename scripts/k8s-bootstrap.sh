#!/bin/bash

# =============================================================================
# ML Inference Infrastructure - Kubernetes Bootstrap Script
# =============================================================================
#
# This script deploys the complete ML inference infrastructure on Kubernetes:
#   - MinIO (S3-compatible storage)
#   - Redis (Feature caching)
#   - PostgreSQL (MLflow backend store)
#   - MLflow (Model registry & tracking)
#   - Prometheus + Grafana (Monitoring)
#   - Inference API (FastAPI application)
#
# TESTED: Docker Desktop Kubernetes (ARM64/Apple Silicon)
#
# Usage:
#   ./scripts/k8s-bootstrap.sh              # Deploy everything
#   ./scripts/k8s-bootstrap.sh --infra-only # Deploy infrastructure only
#   ./scripts/k8s-bootstrap.sh --api-only   # Deploy API only (requires infra)
#   ./scripts/k8s-bootstrap.sh --cleanup    # Remove all deployments
#   ./scripts/k8s-bootstrap.sh --status     # Show deployment status
#
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="${NAMESPACE:-ml-pipeline}"
RELEASE_PREFIX="${RELEASE_PREFIX:-ml}"
IMAGE_TAG="${IMAGE_TAG:-1.0.0}"

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
K8S_DIR="$ROOT_DIR/k8s"

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

log_step() {
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

check_prerequisites() {
    log_step "Checking Prerequisites"

    local missing_deps=()

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        missing_deps+=("kubectl")
    fi

    # Check helm
    if ! command -v helm &> /dev/null; then
        missing_deps+=("helm")
    fi

    # Check docker
    if ! command -v docker &> /dev/null; then
        missing_deps+=("docker")
    fi

    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        log_info "Please install the missing tools and try again."
        exit 1
    fi

    # Check cluster connection
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster."
        log_info "Make sure your kubeconfig is set up correctly."
        log_info "For Docker Desktop: Enable Kubernetes in Docker Desktop settings."
        exit 1
    fi

    log_success "All prerequisites met."
}

add_helm_repos() {
    log_info "Adding Helm repositories..."

    helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
    helm repo add community-charts https://community-charts.github.io/helm-charts 2>/dev/null || true
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
    helm repo update

    log_success "Helm repositories updated."
}

create_namespace() {
    log_info "Creating namespace: $NAMESPACE"
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    log_success "Namespace ready."
}

wait_for_pods() {
    local label=$1
    local timeout=${2:-120}

    log_info "Waiting for pods with label '$label' to be ready..."
    kubectl wait --for=condition=ready pod -l "$label" -n "$NAMESPACE" --timeout="${timeout}s" 2>/dev/null || {
        log_warn "Some pods may not be ready yet. Continuing..."
    }
}

# =============================================================================
# Infrastructure Deployment Functions
# =============================================================================

deploy_minio() {
    log_step "Deploying MinIO"

    helm upgrade --install "${RELEASE_PREFIX}-minio" bitnami/minio \
        --namespace "$NAMESPACE" \
        --values "$ROOT_DIR/minio/values.yaml" \
        --wait --timeout 5m

    wait_for_pods "app.kubernetes.io/name=minio"
    log_success "MinIO deployed."
}

deploy_redis() {
    log_step "Deploying Redis"

    helm upgrade --install "${RELEASE_PREFIX}-redis" bitnami/redis \
        --namespace "$NAMESPACE" \
        --values "$ROOT_DIR/redis/values.yaml" \
        --wait --timeout 5m

    wait_for_pods "app.kubernetes.io/name=redis"
    log_success "Redis deployed."
}

deploy_postgresql() {
    log_step "Deploying PostgreSQL"

    # Deploy PostgreSQL using a simple manifest (avoiding Bitnami subscription issues)
    cat <<EOF | kubectl apply -n "$NAMESPACE" -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgresql
  labels:
    app: postgresql
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgresql
  template:
    metadata:
      labels:
        app: postgresql
    spec:
      containers:
      - name: postgresql
        image: postgres:14-alpine
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_DB
          value: mlflow
        - name: POSTGRES_USER
          value: mlflow
        - name: POSTGRES_PASSWORD
          value: mlflow123
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
        livenessProbe:
          exec:
            command: ["pg_isready", "-U", "mlflow"]
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command: ["pg_isready", "-U", "mlflow"]
          initialDelaySeconds: 5
          periodSeconds: 5
      volumes:
      - name: data
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: postgresql
spec:
  selector:
    app: postgresql
  ports:
  - port: 5432
    targetPort: 5432
EOF

    wait_for_pods "app=postgresql"
    log_success "PostgreSQL deployed."
}

deploy_mlflow() {
    log_step "Deploying MLflow"

    helm upgrade --install "${RELEASE_PREFIX}-mlflow" community-charts/mlflow \
        --namespace "$NAMESPACE" \
        --values "$ROOT_DIR/mlflow/values.yaml" \
        --wait --timeout 10m

    wait_for_pods "app.kubernetes.io/name=mlflow"
    log_success "MLflow deployed."
}

deploy_monitoring() {
    log_step "Deploying Prometheus + Grafana"

    helm upgrade --install "${RELEASE_PREFIX}-monitoring" prometheus-community/kube-prometheus-stack \
        --namespace "$NAMESPACE" \
        --values "$ROOT_DIR/grafana/values.yaml" \
        --wait --timeout 10m

    wait_for_pods "app.kubernetes.io/name=grafana"
    log_success "Monitoring stack deployed."
}

deploy_infrastructure() {
    log_step "Deploying Infrastructure Services"

    deploy_minio
    deploy_redis
    deploy_postgresql
    deploy_mlflow
    deploy_monitoring

    log_success "All infrastructure services deployed!"
}

# =============================================================================
# API Deployment Functions
# =============================================================================

build_api_image() {
    log_step "Building API Docker Image"

    docker build -t crypto-prediction-api:${IMAGE_TAG} \
        -f "$ROOT_DIR/docker/Dockerfile.inference" \
        "$ROOT_DIR"

    log_success "API image built: crypto-prediction-api:${IMAGE_TAG}"
}

create_secrets() {
    log_step "Creating Kubernetes Secrets"

    # Generate base64 encoded secrets
    DB_PASSWORD_B64=$(echo -n "mlflow123" | base64)
    MINIO_ACCESS_B64=$(echo -n "admin" | base64)
    MINIO_SECRET_B64=$(echo -n "admin123" | base64)
    REDIS_PASSWORD_B64=$(echo -n "redis123" | base64)

    cat <<EOF | kubectl apply -n "$NAMESPACE" -f -
apiVersion: v1
kind: Secret
metadata:
  name: ml-pipeline-secrets
  labels:
    app: crypto-prediction-api
    component: secrets
type: Opaque
data:
  DB_PASSWORD: ${DB_PASSWORD_B64}
  MINIO_ACCESS_KEY: ${MINIO_ACCESS_B64}
  MINIO_SECRET_KEY: ${MINIO_SECRET_B64}
  REDIS_PASSWORD: ${REDIS_PASSWORD_B64}
EOF

    log_success "Secrets created."
}

deploy_api() {
    log_step "Deploying Inference API"

    build_api_image
    create_secrets

    # Apply API manifests using kustomize
    kubectl apply -k "$K8S_DIR"

    # Wait for deployment
    kubectl rollout status deployment/crypto-prediction-api -n "$NAMESPACE" --timeout=5m

    log_success "Inference API deployed."
}

# =============================================================================
# Status & Verification Functions
# =============================================================================

show_status() {
    log_step "Deployment Status"

    echo -e "${CYAN}Pods:${NC}"
    kubectl get pods -n "$NAMESPACE" -o wide
    echo ""

    echo -e "${CYAN}Services:${NC}"
    kubectl get svc -n "$NAMESPACE"
    echo ""

    echo -e "${CYAN}HPA:${NC}"
    kubectl get hpa -n "$NAMESPACE" 2>/dev/null || echo "No HPA found"
    echo ""
}

show_endpoints() {
    log_step "Service Access Information"

    echo -e "${CYAN}To access services, use port-forward:${NC}\n"
    echo "  API:      kubectl port-forward -n $NAMESPACE svc/crypto-prediction-api 8000:8000"
    echo "  MLflow:   kubectl port-forward -n $NAMESPACE svc/${RELEASE_PREFIX}-mlflow 5000:5000"
    echo "  MinIO:    kubectl port-forward -n $NAMESPACE svc/${RELEASE_PREFIX}-minio 9000:9000"
    echo "  Grafana:  kubectl port-forward -n $NAMESPACE svc/${RELEASE_PREFIX}-monitoring-grafana 3000:80"
    echo ""
    echo -e "${CYAN}Default credentials:${NC}"
    echo "  MinIO:   admin / admin123"
    echo "  Grafana: admin / prom-operator (or check values.yaml)"
    echo "  MLflow:  No auth (open)"
    echo ""
}

verify_services() {
    log_step "Verifying Service Connectivity"

    local failed=0

    # Test API health
    log_info "Testing API..."
    kubectl exec -n "$NAMESPACE" deployment/crypto-prediction-api -- \
        curl -s http://localhost:8000/health > /dev/null 2>&1 && \
        log_success "API is healthy" || { log_error "API health check failed"; ((failed++)); }

    # Test MLflow
    log_info "Testing MLflow..."
    kubectl exec -n "$NAMESPACE" deployment/crypto-prediction-api -- \
        curl -s http://${RELEASE_PREFIX}-mlflow:5000/health > /dev/null 2>&1 && \
        log_success "MLflow is accessible" || { log_error "MLflow not accessible"; ((failed++)); }

    # Test MinIO
    log_info "Testing MinIO..."
    kubectl exec -n "$NAMESPACE" deployment/crypto-prediction-api -- \
        curl -s http://${RELEASE_PREFIX}-minio:9000/minio/health/live > /dev/null 2>&1 && \
        log_success "MinIO is accessible" || { log_warn "MinIO health check - may need different endpoint"; }

    # Test Redis
    log_info "Testing Redis..."
    kubectl exec -n "$NAMESPACE" deployment/crypto-prediction-api -- \
        python3 -c "import redis; r = redis.Redis(host='${RELEASE_PREFIX}-redis-master', port=6379, password='redis123'); print('OK' if r.ping() else 'FAIL')" 2>/dev/null | grep -q "OK" && \
        log_success "Redis is accessible" || { log_error "Redis not accessible"; ((failed++)); }

    if [ $failed -eq 0 ]; then
        log_success "All services verified!"
    else
        log_warn "$failed service(s) failed verification"
    fi
}

# =============================================================================
# Cleanup Functions
# =============================================================================

cleanup() {
    log_step "Cleanup"

    log_warn "This will delete all deployments in namespace: $NAMESPACE"
    read -p "Are you sure? (yes/no): " confirm

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
    kubectl delete -k "$K8S_DIR" 2>/dev/null || true

    log_info "Deleting PostgreSQL..."
    kubectl delete deployment postgresql -n "$NAMESPACE" 2>/dev/null || true
    kubectl delete svc postgresql -n "$NAMESPACE" 2>/dev/null || true

    log_info "Deleting secrets..."
    kubectl delete secret ml-pipeline-secrets -n "$NAMESPACE" 2>/dev/null || true

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
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Deploy ML inference infrastructure on Kubernetes."
    echo ""
    echo "Options:"
    echo "  (no args)       Deploy everything (infrastructure + API)"
    echo "  --infra-only    Deploy infrastructure services only"
    echo "  --api-only      Deploy API only (requires infrastructure)"
    echo "  --status        Show deployment status"
    echo "  --endpoints     Show service access information"
    echo "  --verify        Verify service connectivity"
    echo "  --cleanup       Remove all deployments"
    echo "  --help          Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  NAMESPACE       Kubernetes namespace (default: ml-pipeline)"
    echo "  RELEASE_PREFIX  Helm release prefix (default: ml)"
    echo "  IMAGE_TAG       API image tag (default: 1.0.0)"
    echo ""
    echo "Examples:"
    echo "  $0                    # Full deployment"
    echo "  $0 --infra-only       # Deploy only infrastructure"
    echo "  $0 --status           # Check status"
    echo "  $0 --verify           # Verify connectivity"
    echo "  $0 --cleanup          # Remove everything"
}

main() {
    case "${1:-}" in
        --infra-only)
            check_prerequisites
            add_helm_repos
            create_namespace
            deploy_infrastructure
            show_status
            show_endpoints
            ;;
        --api-only)
            check_prerequisites
            create_namespace
            deploy_api
            show_status
            ;;
        --status)
            show_status
            ;;
        --endpoints)
            show_endpoints
            ;;
        --verify)
            verify_services
            ;;
        --cleanup)
            cleanup
            ;;
        --help|-h)
            usage
            ;;
        "")
            # Full deployment
            check_prerequisites
            add_helm_repos
            create_namespace
            deploy_infrastructure
            deploy_api
            show_status
            show_endpoints
            verify_services

            log_step "Deployment Complete!"
            echo -e "${GREEN}Your ML inference infrastructure is ready!${NC}"
            echo ""
            echo "Next steps:"
            echo "  1. Port-forward the API: kubectl port-forward -n $NAMESPACE svc/crypto-prediction-api 8000:8000"
            echo "  2. Test the API: curl http://localhost:8000/health"
            echo "  3. View API docs: http://localhost:8000/docs"
            echo "  4. Run validation: ./scripts/validate-deployment.sh --env k8s"
            echo ""
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
}

main "$@"
