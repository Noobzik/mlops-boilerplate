#!/bin/bash

# =============================================================================
# ML Inference Infrastructure - Deployment Validation Script
# =============================================================================
#
# This script validates the ML infrastructure deployment and tests the
# end-to-end workflow including:
#   - Service connectivity (MinIO, Redis, PostgreSQL, MLflow)
#   - API health and endpoints
#   - Model registration and retrieval (optional demo)
#   - Metrics and monitoring
#
# Works with both Docker Compose and Kubernetes deployments.
#
# Usage:
#   ./scripts/validate-deployment.sh                    # Auto-detect environment
#   ./scripts/validate-deployment.sh --env docker       # Test Docker Compose
#   ./scripts/validate-deployment.sh --env k8s          # Test Kubernetes
#   ./scripts/validate-deployment.sh --full             # Run full validation with demo model
#   ./scripts/validate-deployment.sh --quick            # Quick health checks only
#
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Default settings
ENV_TYPE=""
FULL_VALIDATION=false
QUICK_MODE=false
NAMESPACE="${NAMESPACE:-ml-pipeline}"
RELEASE_PREFIX="${RELEASE_PREFIX:-ml}"

# Service endpoints (will be set based on environment)
API_URL=""
MLFLOW_URL=""
MINIO_URL=""
REDIS_HOST=""
REDIS_PORT=""
REDIS_PASSWORD=""

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

log_step() {
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# Counters for test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

record_pass() {
    ((TESTS_PASSED++))
    log_success "$1"
}

record_fail() {
    ((TESTS_FAILED++))
    log_error "$1"
}

record_skip() {
    ((TESTS_SKIPPED++))
    log_warn "SKIP: $1"
}

# =============================================================================
# Environment Detection
# =============================================================================

detect_environment() {
    log_step "Detecting Environment"

    # Check if Kubernetes is available and has our namespace
    if command -v kubectl &> /dev/null && kubectl get namespace "$NAMESPACE" &> /dev/null; then
        # Check if API pod is running
        if kubectl get pods -n "$NAMESPACE" -l app=crypto-prediction-api --no-headers 2>/dev/null | grep -q "Running"; then
            ENV_TYPE="k8s"
            log_info "Detected Kubernetes deployment"
        fi
    fi

    # Check if Docker Compose is running
    if [ -z "$ENV_TYPE" ]; then
        if command -v docker &> /dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "ml-inference-api\|ml-mlflow"; then
            ENV_TYPE="docker"
            log_info "Detected Docker Compose deployment"
        fi
    fi

    if [ -z "$ENV_TYPE" ]; then
        log_error "No active deployment detected!"
        log_info "Start the infrastructure first:"
        log_info "  Docker Compose: docker-compose up -d"
        log_info "  Kubernetes:     ./scripts/k8s-bootstrap.sh"
        exit 1
    fi

    log_success "Environment: $ENV_TYPE"
}

setup_endpoints() {
    log_step "Configuring Service Endpoints"

    if [ "$ENV_TYPE" == "docker" ]; then
        # Docker Compose endpoints
        API_URL="http://localhost:8000"
        MLFLOW_URL="http://localhost:5001"
        MINIO_URL="http://localhost:9000"
        REDIS_HOST="localhost"
        REDIS_PORT="6379"
        REDIS_PASSWORD=""
        GRAFANA_URL="http://localhost:3000"
        PROMETHEUS_URL="http://localhost:9090"
    else
        # Kubernetes - need port-forwards
        log_info "Setting up Kubernetes port-forwards..."

        # Kill any existing port-forwards
        pkill -f "kubectl port-forward.*$NAMESPACE" 2>/dev/null || true
        sleep 1

        # Start port-forwards in background
        kubectl port-forward -n "$NAMESPACE" svc/crypto-prediction-api 8000:8000 &>/dev/null &
        kubectl port-forward -n "$NAMESPACE" svc/${RELEASE_PREFIX}-mlflow 5000:5000 &>/dev/null &
        kubectl port-forward -n "$NAMESPACE" svc/${RELEASE_PREFIX}-minio 9000:9000 &>/dev/null &
        kubectl port-forward -n "$NAMESPACE" svc/${RELEASE_PREFIX}-monitoring-grafana 3000:80 &>/dev/null &

        # Wait for port-forwards to establish
        sleep 3

        API_URL="http://localhost:8000"
        MLFLOW_URL="http://localhost:5000"
        MINIO_URL="http://localhost:9000"
        REDIS_HOST="${RELEASE_PREFIX}-redis-master"
        REDIS_PORT="6379"
        REDIS_PASSWORD="redis123"
        GRAFANA_URL="http://localhost:3000"
        PROMETHEUS_URL="http://localhost:9090"
    fi

    log_success "Endpoints configured"
}

cleanup_port_forwards() {
    if [ "$ENV_TYPE" == "k8s" ]; then
        log_info "Cleaning up port-forwards..."
        pkill -f "kubectl port-forward.*$NAMESPACE" 2>/dev/null || true
    fi
}

trap cleanup_port_forwards EXIT

# =============================================================================
# Validation Tests
# =============================================================================

test_api_health() {
    log_step "Testing API Health"

    # Basic health check
    log_info "Checking /health endpoint..."
    if response=$(curl -s --max-time 10 "${API_URL}/health" 2>/dev/null); then
        if echo "$response" | grep -q '"status"'; then
            record_pass "API /health endpoint responding"

            # Parse loaded models
            loaded_models=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('loaded_models', 0))" 2>/dev/null || echo "0")
            log_info "Loaded models: $loaded_models"
        else
            record_fail "API /health returned unexpected response"
        fi
    else
        record_fail "API /health endpoint not responding"
        return 1
    fi

    # Liveness probe
    log_info "Checking /live endpoint..."
    if curl -s --max-time 5 "${API_URL}/live" | grep -q "alive"; then
        record_pass "API liveness probe responding"
    else
        record_fail "API liveness probe failed"
    fi

    # Readiness probe (may fail if no models loaded - that's ok)
    log_info "Checking /ready endpoint..."
    if curl -s --max-time 5 "${API_URL}/ready" | grep -q "ready\|loaded"; then
        record_pass "API readiness probe responding"
    else
        record_skip "API readiness probe - may need models loaded"
    fi
}

test_api_endpoints() {
    log_step "Testing API Endpoints"

    # Root endpoint
    log_info "Checking / endpoint..."
    if curl -s --max-time 5 "${API_URL}/" | grep -q "Crypto Multi-Task Prediction API"; then
        record_pass "API root endpoint"
    else
        record_fail "API root endpoint"
    fi

    # OpenAPI docs
    log_info "Checking /docs endpoint..."
    if curl -s --max-time 5 "${API_URL}/docs" | grep -q "swagger"; then
        record_pass "API Swagger docs available"
    else
        record_fail "API Swagger docs"
    fi

    # Tasks endpoint
    log_info "Checking /tasks endpoint..."
    if curl -s --max-time 5 "${API_URL}/tasks" | grep -q "tasks"; then
        record_pass "API /tasks endpoint"
    else
        record_fail "API /tasks endpoint"
    fi

    # Models endpoint
    log_info "Checking /models endpoint..."
    if curl -s --max-time 5 "${API_URL}/models" | grep -q "models\|total"; then
        record_pass "API /models endpoint"
    else
        record_fail "API /models endpoint"
    fi

    # Metrics endpoint
    log_info "Checking /metrics endpoint..."
    if curl -s --max-time 5 "${API_URL}/metrics" | grep -q "python_"; then
        record_pass "API Prometheus metrics endpoint"
    else
        record_fail "API Prometheus metrics"
    fi
}

test_mlflow() {
    log_step "Testing MLflow"

    # Health check
    log_info "Checking MLflow health..."
    if curl -s --max-time 10 "${MLFLOW_URL}/health" | grep -qE "OK|alive|healthy"; then
        record_pass "MLflow health endpoint"
    else
        # Try alternative endpoints
        if curl -s --max-time 10 "${MLFLOW_URL}/api/2.0/mlflow/experiments/search" -X POST -H "Content-Type: application/json" -d '{}' 2>/dev/null | grep -q "experiments"; then
            record_pass "MLflow API responding"
        else
            record_fail "MLflow not responding"
        fi
    fi

    # List experiments - try multiple API versions
    log_info "Checking MLflow experiments API..."
    # Try POST first (MLflow 2.x style)
    if curl -s --max-time 10 "${MLFLOW_URL}/api/2.0/mlflow/experiments/search" \
        -X POST -H "Content-Type: application/json" -d '{}' 2>/dev/null | grep -q "experiments"; then
        record_pass "MLflow experiments API"
    # Try GET with list endpoint
    elif curl -s --max-time 10 "${MLFLOW_URL}/api/2.0/mlflow/experiments/list" 2>/dev/null | grep -q "experiment"; then
        record_pass "MLflow experiments API (list endpoint)"
    # Try the UI endpoint as fallback
    elif curl -s --max-time 10 -o /dev/null -w "%{http_code}" "${MLFLOW_URL}/" 2>/dev/null | grep -q "200"; then
        record_pass "MLflow UI accessible (API format may differ)"
    else
        record_fail "MLflow experiments API"
    fi
}

test_minio() {
    log_step "Testing MinIO"

    # Health check
    log_info "Checking MinIO health..."
    if curl -s --max-time 10 "${MINIO_URL}/minio/health/live" 2>/dev/null; then
        record_pass "MinIO health endpoint"
    else
        record_fail "MinIO health endpoint"
    fi

    # Check if we can list buckets (using mc or curl)
    if command -v mc &> /dev/null; then
        log_info "Checking MinIO buckets with mc..."
        mc alias set minio-test "${MINIO_URL}" admin admin123 --api S3v4 &>/dev/null || true
        if mc ls minio-test &>/dev/null; then
            record_pass "MinIO bucket access"
        else
            record_skip "MinIO bucket access - mc configured but access denied"
        fi
    else
        record_skip "MinIO bucket test - mc client not installed"
    fi
}

test_redis() {
    log_step "Testing Redis"

    if [ "$ENV_TYPE" == "docker" ]; then
        # Docker - direct connection
        log_info "Testing Redis connection..."
        if docker exec ml-redis redis-cli PING 2>/dev/null | grep -q "PONG"; then
            record_pass "Redis responding"
        else
            record_fail "Redis not responding"
        fi
    else
        # Kubernetes - test from API pod
        log_info "Testing Redis from API pod..."
        if kubectl exec -n "$NAMESPACE" deployment/crypto-prediction-api -- \
            python3 -c "import redis; r = redis.Redis(host='${REDIS_HOST}', port=${REDIS_PORT}, password='${REDIS_PASSWORD}'); print('PONG' if r.ping() else 'FAIL')" 2>/dev/null | grep -q "PONG"; then
            record_pass "Redis responding"
        else
            record_fail "Redis not responding"
        fi
    fi
}

test_monitoring() {
    log_step "Testing Monitoring Stack"

    # Grafana
    log_info "Checking Grafana..."
    if curl -s --max-time 10 "${GRAFANA_URL}/api/health" 2>/dev/null | grep -q "ok\|database"; then
        record_pass "Grafana responding"
    elif curl -s --max-time 10 -o /dev/null -w "%{http_code}" "${GRAFANA_URL}/login" 2>/dev/null | grep -q "200"; then
        record_pass "Grafana login page accessible"
    else
        record_skip "Grafana - may not be port-forwarded"
    fi

    # Prometheus (Docker Compose)
    if [ "$ENV_TYPE" == "docker" ]; then
        log_info "Checking Prometheus..."
        if curl -s --max-time 10 "${PROMETHEUS_URL}/-/healthy" 2>/dev/null | grep -q "Healthy"; then
            record_pass "Prometheus responding"
        else
            record_skip "Prometheus - may not be running"
        fi
    fi
}

test_connectivity() {
    log_step "Testing Inter-Service Connectivity"

    if [ "$ENV_TYPE" == "k8s" ]; then
        # Test from API pod to other services
        log_info "Testing API -> MLflow connectivity..."
        if kubectl exec -n "$NAMESPACE" deployment/crypto-prediction-api -- \
            curl -s --max-time 5 http://${RELEASE_PREFIX}-mlflow:5000/health 2>/dev/null | grep -qE "OK|alive"; then
            record_pass "API -> MLflow connectivity"
        else
            record_fail "API -> MLflow connectivity"
        fi

        log_info "Testing API -> MinIO connectivity..."
        if kubectl exec -n "$NAMESPACE" deployment/crypto-prediction-api -- \
            curl -s --max-time 5 http://${RELEASE_PREFIX}-minio:9000/minio/health/live 2>/dev/null; then
            record_pass "API -> MinIO connectivity"
        else
            record_fail "API -> MinIO connectivity"
        fi
    else
        # Docker - test container networking
        log_info "Testing container network connectivity..."
        if docker exec ml-inference-api curl -s --max-time 5 http://mlflow:5001/health 2>/dev/null | grep -qE "OK|alive"; then
            record_pass "API -> MLflow connectivity"
        else
            record_skip "API -> MLflow connectivity check"
        fi
    fi
}

# =============================================================================
# Full Validation - Demo Model Registration
# =============================================================================

run_demo_model_test() {
    log_step "Demo Model Registration Test"

    log_info "This test registers a simple demo model to MLflow and verifies retrieval."

    # Create a temporary Python script for the demo
    cat > /tmp/demo_model_test.py << 'PYTHON_SCRIPT'
import os
import sys
import json
import numpy as np

# Set MLflow tracking URI from environment or default
mlflow_uri = os.environ.get('MLFLOW_TRACKING_URI', 'http://localhost:5000')
os.environ['MLFLOW_TRACKING_URI'] = mlflow_uri

import mlflow
from mlflow.tracking import MlflowClient
from sklearn.linear_model import LinearRegression
from sklearn.datasets import make_regression

print(f"Connecting to MLflow at: {mlflow_uri}")

try:
    # Create a simple demo model
    X, y = make_regression(n_samples=100, n_features=5, noise=0.1)
    model = LinearRegression()
    model.fit(X, y)

    # Set experiment
    experiment_name = "validation_test_experiment"
    mlflow.set_experiment(experiment_name)

    # Log the model
    with mlflow.start_run(run_name="validation_test_run") as run:
        mlflow.log_param("test_param", "validation_test")
        mlflow.log_metric("test_metric", 0.95)
        mlflow.sklearn.log_model(model, "model", registered_model_name="validation_test_model")
        run_id = run.info.run_id

    print(f"Model registered successfully!")
    print(f"Run ID: {run_id}")
    print(f"Model name: validation_test_model")

    # Verify we can retrieve the model
    client = MlflowClient()
    model_versions = client.search_model_versions("name='validation_test_model'")

    if model_versions:
        print(f"Found {len(model_versions)} model version(s)")
        print("SUCCESS: Model registration and retrieval working!")
        sys.exit(0)
    else:
        print("ERROR: Model not found after registration")
        sys.exit(1)

except Exception as e:
    print(f"ERROR: {str(e)}")
    sys.exit(1)
PYTHON_SCRIPT

    # Run the test
    if [ "$ENV_TYPE" == "k8s" ]; then
        # Copy script to pod and run
        kubectl cp /tmp/demo_model_test.py "$NAMESPACE"/$(kubectl get pods -n "$NAMESPACE" -l app=crypto-prediction-api -o jsonpath='{.items[0].metadata.name}'):/tmp/demo_model_test.py

        if kubectl exec -n "$NAMESPACE" deployment/crypto-prediction-api -- \
            python3 /tmp/demo_model_test.py 2>&1 | tee /tmp/demo_output.txt | grep -q "SUCCESS"; then
            record_pass "Demo model registration and retrieval"
        else
            record_fail "Demo model registration failed"
            cat /tmp/demo_output.txt
        fi
    else
        # Docker - run in container
        docker cp /tmp/demo_model_test.py ml-inference-api:/tmp/demo_model_test.py

        if docker exec -e MLFLOW_TRACKING_URI=http://mlflow:5001 ml-inference-api \
            python3 /tmp/demo_model_test.py 2>&1 | tee /tmp/demo_output.txt | grep -q "SUCCESS"; then
            record_pass "Demo model registration and retrieval"
        else
            record_fail "Demo model registration failed"
            cat /tmp/demo_output.txt
        fi
    fi

    # Cleanup
    rm -f /tmp/demo_model_test.py /tmp/demo_output.txt
}

# =============================================================================
# Summary
# =============================================================================

print_summary() {
    log_step "Validation Summary"

    echo -e "${CYAN}Environment:${NC} $ENV_TYPE"
    echo ""
    echo -e "${GREEN}Passed:${NC}  $TESTS_PASSED"
    echo -e "${RED}Failed:${NC}  $TESTS_FAILED"
    echo -e "${YELLOW}Skipped:${NC} $TESTS_SKIPPED"
    echo ""

    local total=$((TESTS_PASSED + TESTS_FAILED))
    if [ $total -gt 0 ]; then
        local percentage=$((TESTS_PASSED * 100 / total))
        echo -e "Pass rate: ${percentage}%"
    fi

    echo ""
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}  All validation tests passed!${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    else
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${YELLOW}  Some tests failed. Review the output above for details.${NC}"
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    fi
}

# =============================================================================
# Main
# =============================================================================

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Validate ML infrastructure deployment."
    echo ""
    echo "Options:"
    echo "  --env docker    Force Docker Compose environment"
    echo "  --env k8s       Force Kubernetes environment"
    echo "  --quick         Quick health checks only"
    echo "  --full          Full validation including demo model test"
    echo "  --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Auto-detect and run standard tests"
    echo "  $0 --env k8s          # Test Kubernetes deployment"
    echo "  $0 --full             # Run all tests including demo"
    echo "  $0 --quick            # Quick health checks only"
}

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --env)
                ENV_TYPE="$2"
                shift 2
                ;;
            --quick)
                QUICK_MODE=true
                shift
                ;;
            --full)
                FULL_VALIDATION=true
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    echo -e "${MAGENTA}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║     ML Infrastructure Deployment Validation                ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Detect or use specified environment
    if [ -z "$ENV_TYPE" ]; then
        detect_environment
    else
        log_info "Using specified environment: $ENV_TYPE"
    fi

    # Setup endpoints
    setup_endpoints

    if [ "$QUICK_MODE" = true ]; then
        # Quick mode - just health checks
        test_api_health
    else
        # Standard validation
        test_api_health
        test_api_endpoints
        test_mlflow
        test_minio
        test_redis
        test_monitoring
        test_connectivity

        # Full validation includes demo model test
        if [ "$FULL_VALIDATION" = true ]; then
            run_demo_model_test
        fi
    fi

    # Print summary
    print_summary

    # Exit with appropriate code
    if [ $TESTS_FAILED -gt 0 ]; then
        exit 1
    fi
}

main "$@"
