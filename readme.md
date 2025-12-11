# Crypto ML Pipeline

A production-grade machine learning pipeline for cryptocurrency price prediction using multi-task learning. The system includes enterprise MLOps infrastructure with Airflow orchestration, DVC data versioning, MLflow model registry, and comprehensive monitoring capabilities.

## Features

### What's Working Now
- **Multi-Task Learning**: Trains 7 different prediction tasks simultaneously (price returns, direction classification, volatility prediction)
- **Airflow Orchestration**: Fully automated pipeline for data quality assessment, feature engineering, validation, versioning, and model training
- **DVC Data Versioning**: Git-based data versioning with S3/MinIO backend for reproducibility
- **MLflow Model Registry**: Complete experiment tracking with stage-based model promotion workflow (Training → Staging → Production)
- **MinIO Storage**: S3-compatible storage for models and engineered features
- **Monitoring Infrastructure**: Prometheus and Grafana configuration files ready for activation
- **Secure Configuration**: NEW - Environment-based secrets management eliminates all hardcoded credentials

### Currently In Development
- **Production API Deployment**: FastAPI service code is complete but needs Kubernetes deployment manifests
- **Production Inference Pipeline**: Inference logic exists and works locally, requires production deployment setup
- **CI/CD Pipeline**: GitHub Actions workflows need to be configured
- **Automated Testing**: Test infrastructure and test cases need to be built
- **Metrics Instrumentation**: Prometheus metrics code needs to be integrated into the pipeline

### Planned for Future
- **Real-time Inference**: Deploy API with auto-scaling capabilities
- **Model Serving Automation**: Streamlined production model deployment
- **Live Monitoring Dashboards**: Activate Grafana with real-time metrics
- **Error Tracking Integration**: Sentry setup for production error monitoring

## Project Structure

```
.
├── src/
│   └── config/                 # Centralized configuration management
│       ├── __init__.py
│       └── settings.py         # Pydantic settings with environment loading
├── dags/                       # Airflow DAGs and pipeline logic
│   ├── ml_dags_processing.py   # Main pipeline orchestration
│   ├── model_training.py       # Multi-task model training with MLflow
│   ├── feature_eng.py          # 50+ engineered features
│   ├── data_versioning.py      # DVC integration
│   ├── automated_data_validation.py  # Multi-layer validation
│   ├── model_promotion.py      # Automated model promotion
│   ├── data_quality.py         # Data quality assessment
│   ├── inference_feature_pipeline.py  # Production inference
│   └── viz.py                  # Monitoring and visualization
├── app/
│   ├── production_api.py       # FastAPI prediction service
│   ├── Dockerfile              # API container
│   └── requirements.txt        # API dependencies
├── k8s/
│   └── secrets.yaml.example    # Kubernetes secrets template
├── airflow/                    # Airflow Helm values
├── grafana/                    # Grafana Helm values
├── minio/                      # MinIO Helm values
├── mlflow/                     # MLflow Helm values
├── .env.example                # Environment template (safe to commit)
├── .env.development            # Development config (gitignored)
├── .env.production             # Production config (gitignored)
├── Dockerfile                  # Airflow container
├── requirements.txt            # Pipeline dependencies
└── README.md                   # This file
```

## Quick Start

### 1. Clone and Install Dependencies

```bash
git clone https://github.com/yourusername/ml-eng-with-ops.git
cd ml-eng-with-ops

# Install dependencies
pip install -r requirements.txt
```

### 2. Configure Your Environment

**For Local Development:**

```bash
# Copy the environment template
cp .env.example .env.development

# Edit with your local credentials
nano .env.development

# Set environment variable
export ENVIRONMENT=development
```

**Key variables you need to configure:**
```bash
# Database credentials
DB_HOST=localhost
DB_PORT=5432
DB_USER=your_user
DB_PASSWORD=your_password  # NEVER commit this file!

# MinIO credentials
MINIO_ENDPOINT=minio:9000
MINIO_ACCESS_KEY=admin
MINIO_SECRET_KEY=your_secret  # NEVER commit this file!

# See .env.example for the complete list
```

**For Production (Kubernetes):**

```bash
# Create your secrets file from the template
cp k8s/secrets.yaml.example k8s/secrets.yaml

# Encode your secrets to base64
echo -n "your_password" | base64

# Fill in the base64 encoded values in k8s/secrets.yaml
# Then apply to your cluster
kubectl apply -f k8s/secrets.yaml
```

### 3. Build Docker Images

```bash
# Build Airflow image
docker build -t custom-airflow:0.0.4 .

# Build API image
cd app && docker build -t crypto-prediction-api:latest .
```

### 4. Deploy Infrastructure (Kubernetes)

```bash
# Install Airflow
helm install airflow apache-airflow/airflow -f airflow/values.yaml

# Install MLflow
helm install mlflow community/mlflow -f mlflow/values.yaml

# Install MinIO
helm install minio bitnami/minio -f minio/values.yaml

# Install Grafana (optional)
helm install grafana grafana/grafana -f grafana/values.yaml
```

### 5. Run the ML Pipeline

**Important Note**: The training pipeline is fully functional and production-ready. The inference/prediction API requires additional deployment setup (see Implementation Roadmap below).

**Access the Airflow UI:**
```bash
kubectl port-forward svc/airflow-webserver 8080:8080
# Open your browser to http://localhost:8080
# Default credentials: admin/admin123
```

**Trigger the Pipeline:**
1. Navigate to the DAGs page
2. Find `crypto_ml_pipeline`
3. Click the play button to trigger

**What Currently Works:**
- Data ingestion from Binance API
- Feature engineering (generates 50+ technical indicators and features)
- Multi-layer data validation
- DVC-based data versioning
- Model training (LightGBM + XGBoost ensemble)
- MLflow model registry and experiment tracking
- Automated model promotion to staging

**What Still Needs Setup:**
- Production API deployment (Kubernetes manifests required)
- Real-time inference endpoint (deployment infrastructure pending)
- Prometheus metrics integration (instrumentation needed)
- Grafana dashboard activation (currently configuration only)

**Monitor Your Pipeline:**
- **Airflow UI**: Check task execution logs and DAG status
- **MLflow**: View experiments and models at http://localhost:5000
- **Grafana**: Dashboard configurations ready at http://localhost:3000 (requires activation)

## ML Pipeline Architecture

### Data Flow

```
Binance API → PostgreSQL
     ↓
Data Quality Assessment
     ↓
Feature Engineering (50+ features)
     ↓
Data Validation (multi-layer)
     ↓
DVC Versioning (Git + S3)
     ↓
Model Training (LightGBM + XGBoost)
     ↓
MLflow Registry (Training → Staging → Production)
     ↓
Production API (FastAPI)
```

### Prediction Tasks

The system trains separate models for each of these tasks:

| Task Name | Type | Time Horizon | Description |
|-----------|------|--------------|-------------|
| `return_1step` | Regression | 15 minutes | Short-term price return prediction |
| `return_4step` | Regression | 1 hour | Medium-term price return prediction |
| `return_16step` | Regression | 4 hours | Long-term price return prediction |
| `direction_4step` | Binary Classification | 1 hour | Price direction (up or down) |
| `direction_multi_4step` | Multi-class Classification (5 classes) | 1 hour | Detailed trend classification |
| `volatility_4step` | Regression | 1 hour | Price volatility prediction |
| `vol_regime_4step` | Multi-class Classification (3 classes) | 1 hour | Volatility regime classification |

### Supported Cryptocurrency Pairs
BTCUSDT, ETHUSDT, BNBUSDT, ADAUSDT, SOLUSDT, XRPUSDT, DOTUSDT, AVAXUSDT, MATICUSDT, LINKUSDT

## Configuration Management

The project uses Pydantic Settings for type-safe, environment-based configuration management.

### How Configuration Works

```python
from src.config import get_settings

settings = get_settings()

# Get database connection parameters
db_config = settings.database.get_connection_dict()

# Get MinIO client configuration
minio_config = settings.minio.get_client_config()

# Access trading symbols
symbols = settings.binance.symbols
```

### Available Configuration Classes

| Configuration Class | Environment Prefix | Purpose |
|---------------------|-------------------|---------|
| `DatabaseConfig` | `DB_` | PostgreSQL connection settings |
| `MinIOConfig` | `MINIO_` | MinIO/S3 storage configuration |
| `RedisConfig` | `REDIS_` | Redis cache settings |
| `MLflowConfig` | `MLFLOW_` | MLflow tracking server configuration |
| `DVCConfig` | `DVC_` | DVC data versioning settings |
| `BinanceConfig` | `BINANCE_` | Binance API configuration |
| `APIConfig` | `API_` | FastAPI server settings |
| `MonitoringConfig` | `MONITORING_` | Prometheus and Sentry configuration |

### Environment Selection

The system automatically loads the correct environment configuration:

```bash
# For development
export ENVIRONMENT=development  # Loads from .env.development

# For staging
export ENVIRONMENT=staging      # Loads from .env.staging

# For production
export ENVIRONMENT=production   # Loads from .env.production or Kubernetes secrets
```

## Security Best Practices

### What You Should Do
- Use environment variables for all sensitive credentials
- Use Kubernetes secrets for production deployments
- Commit the `.env.example` template file (without real values)
- Set file permissions to 600 (read/write for owner only) on .env files
- Rotate secrets regularly according to your security policy
- Use different credentials for development, staging, and production

### What You Should Never Do
- Never commit `.env.development`, `.env.staging`, or `.env.production` files
- Never commit `k8s/secrets.yaml` (only commit the `.example` template)
- Never hardcode credentials directly in source code
- Never share .env files via email, chat, or other insecure channels
- Never log sensitive values like passwords or API keys

## Production API

**Current Status**: The API code is complete and functional. However, deployment to Kubernetes requires additional infrastructure work (deployment manifests, ingress configuration, etc.).

### Testing the API Locally

You can test the API on your local development machine:

```bash
cd app

# Make sure your .env.development is configured
export ENVIRONMENT=development

# Start the API server
uvicorn production_api:app --host 0.0.0.0 --port 8000
```

### Available API Endpoints

All endpoints are implemented and working. They need production deployment infrastructure:

| Endpoint | Method | Implementation Status | Description |
|----------|--------|----------------------|-------------|
| `/health` | GET | Complete (needs K8s probes) | Service health check with model status |
| `/tasks` | GET | Complete | List all available prediction tasks |
| `/models` | GET | Complete | List all loaded models and metadata |
| `/predict/{symbol}` | POST | Complete | Multi-task predictions for a symbol |
| `/predict/batch` | POST | Complete | Batch predictions for multiple symbols |
| `/predict/{symbol}/task/{task}` | GET | Complete | Single task prediction for a symbol |
| `/models/reload` | POST | Complete | Reload models from MLflow registry |
| `/models/promote` | POST | Complete | Promote a model to a different stage |
| `/features/{symbol}` | GET | Complete | Get current feature values (debugging) |

### What's Needed for Production Deployment

Before the API can run in production, these items need to be completed:

1. **Kubernetes Deployment Manifests** - Create YAML files for Deployment, Service, and Ingress resources
2. **Health Check Probes** - Configure liveness and readiness probes in the deployment
3. **Resource Limits** - Define CPU and memory limits and requests
4. **Horizontal Pod Autoscaler** - Set up auto-scaling based on CPU/memory usage
5. **Metrics Endpoint** - Add Prometheus metrics exposition endpoint
6. **Rate Limiting** - Implement production-grade rate limiting middleware
7. **Load Testing** - Validate performance under expected production load

### Example API Request

```bash
# Get predictions for Bitcoin
curl -X POST "http://localhost:8000/predict/BTCUSDT" \
  -H "Content-Type: application/json" \
  -d '{"tasks": ["return_1step", "direction_4step"]}'
```

### Example API Response

```json
{
  "symbol": "BTCUSDT",
  "timestamp": "2024-08-29T14:30:00",
  "predictions": {
    "return_1step": {
      "lightgbm": 0.0023,
      "xgboost": 0.0025,
      "ensemble": 0.0024
    },
    "direction_4step": {
      "lightgbm": 1,
      "xgboost": 1,
      "ensemble": 1
    }
  }
}
```

## Monitoring and Observability

### Prometheus Metrics

The pipeline is designed to export these custom metrics (integration pending):
- `data_quality_score` - Data quality assessment scores by symbol
- `feature_count` - Number of features generated per symbol
- `model_training_duration` - Training time for each model
- `model_performance_rmse` - Model RMSE metrics over time
- `validation_failures` - Count of data validation failures

### Grafana Dashboards

Pre-configured dashboards are available in `ml-dashboard-configmap.yaml` and cover:
- Pipeline execution overview and timing
- Data quality trends over time
- Model performance comparison across algorithms
- Validation failure tracking and alerts

These dashboards need to be imported and activated in your Grafana instance.

### Viewing Logs

```bash
# View Airflow task logs
kubectl logs -f <airflow-pod-name> -n airflow

# View API logs (once deployed)
kubectl logs -f <api-pod-name> -n ml-pipeline
```

## Testing

```bash
# Run the test suite (when tests are implemented)
pytest tests/

# Test that configuration loads correctly
python -c "from src.config import get_settings; print(get_settings().database.host)"

# Test database connection
python -c "import psycopg2; from src.config import get_settings; psycopg2.connect(**get_settings().database.get_connection_dict())"
```

## Troubleshooting

### Configuration Issues

**Problem**: "No module named 'src'"

**Solution**: Make sure you're running from the project root directory, or that the path is added correctly in your code.

**Problem**: "DB_PASSWORD field required"

**Solution**: Create a `.env.development` file with all required variables. See `.env.example` for the template.

### Kubernetes Issues

**Problem**: Pod is failing to start

**Solution**: Check these items:
```bash
# Verify secrets exist
kubectl get secrets -n ml-pipeline

# Check environment variables in the pod
kubectl exec -it <pod-name> -- env | grep DB_

# View pod logs for errors
kubectl logs <pod-name> -n ml-pipeline
```

### MLflow Issues

**Problem**: Models are not being registered

**Solution**: Verify that the MLflow tracking URI is correct and that the MLflow service is accessible from your Airflow pods.

## Implementation Roadmap

### Phase 1: Configuration and Security - COMPLETED

Everything in this phase is done and working:

- [x] Configuration management system using Pydantic
- [x] Environment-based secrets management with .env files
- [x] Kubernetes secrets template created
- [x] All hardcoded credentials removed (11 files refactored)
- [x] Security best practices documented and .gitignore updated

### Phase 2: Production Deployment - IN PROGRESS (Next Priority)

**Estimated time**: 2-3 weeks

**Inference and Deployment (Critical Priority)**
- [ ] Create Kubernetes deployment manifests for FastAPI service (Deployment, Service, Ingress)
- [ ] Set up production inference pipeline deployment to Kubernetes
- [ ] Configure automated model loading from MLflow registry
- [ ] Implement health check and readiness probe endpoints
- [ ] Configure Horizontal Pod Autoscaler with appropriate CPU/memory targets
- [ ] Set up load balancing and Ingress with SSL/TLS termination

**Testing and CI/CD**
- [ ] Build unit test suite using pytest (target 60% coverage minimum)
- [ ] Create integration tests for end-to-end pipeline validation
- [ ] Configure GitHub Actions for CI/CD (automated testing and deployment)
- [ ] Set up automated Docker image builds and registry pushes
- [ ] Create staging environment for pre-production testing

### Phase 3: Production Readiness - PLANNED

**Estimated time**: 3-4 weeks

**Monitoring and Observability**
- [ ] Integrate Prometheus metrics into all API endpoints
- [ ] Activate Grafana dashboards with live metrics
- [ ] Implement structured logging with JSON format and correlation IDs
- [ ] Set up error tracking with Sentry for production error monitoring
- [ ] Add distributed tracing with OpenTelemetry
- [ ] Configure alerting rules and notifications (PagerDuty or Slack)

**API Enhancements**
- [ ] Implement rate limiting with per-client request throttling
- [ ] Add authentication system (JWT or OAuth2)
- [ ] Create API versioning structure (v1, v2 endpoints)
- [ ] Enhance request validation with comprehensive Pydantic models
- [ ] Implement response caching using Redis
- [ ] Improve API documentation in Swagger/OpenAPI

**Error Handling Improvements**
- [ ] Create custom exception class hierarchy
- [ ] Implement retry mechanisms with exponential backoff
- [ ] Add circuit breakers to prevent cascade failures
- [ ] Design graceful degradation strategies
- [ ] Standardize error response format across all endpoints

### Phase 4: Code Quality - PLANNED

**Estimated time**: 2-3 weeks

- [ ] Restructure code into modular packages (src/data, src/models, src/features, etc.)
- [ ] Add comprehensive type hints with mypy validation
- [ ] Configure linting tools (black, isort, flake8, ruff)
- [ ] Set up pre-commit hooks for automated formatting and validation
- [ ] Write docstrings for all public APIs
- [ ] Create architecture diagrams using C4 model

### Phase 5: Advanced MLOps - FUTURE

**Estimated time**: 4-6 weeks

- [ ] Integrate model drift detection using Evidently AI
- [ ] Build A/B testing framework for model experimentation
- [ ] Integrate feature store (Feast or Tecton)
- [ ] Implement online feature serving for real-time predictions
- [ ] Set up shadow deployments and canary releases
- [ ] Add automated hyperparameter tuning pipeline
- [ ] Integrate model explainability tools (SHAP or LIME)
- [ ] Implement comprehensive data quality monitoring with Great Expectations

## Current Project Status

### Component Status

| Component | Status | Completion Percentage |
|-----------|--------|----------------------|
| ML Training Pipeline | Implemented and Working | 100% |
| Data Versioning (DVC) | Implemented and Working | 100% |
| Model Registry (MLflow) | Implemented and Working | 100% |
| Configuration Management | Just Completed | 100% |
| API Code | Implemented | 100% |
| API Deployment | Infrastructure Needed | 0% |
| Production Inference | Partially Ready | 20% |
| Testing Infrastructure | Not Started | 0% |
| CI/CD Pipeline | Not Started | 0% |
| Active Monitoring | Configuration Only | 30% |
| Error Handling | Basic Implementation | 40% |

**Overall Project Completion**: Approximately 65%

### Critical Blockers for Production

These items are preventing full production deployment:

1. **API Deployment to Kubernetes** (Critical) - Needs deployment manifests and infrastructure
2. **Production Inference Pipeline** (Critical) - Needs production deployment and testing
3. **Automated Testing** (High Priority) - Required for confidence in deployments
4. **CI/CD Pipeline** (High Priority) - Needed for automated deployments and rollbacks

## Documentation

- **API Documentation**: Interactive docs available at http://localhost:8000/docs (Swagger UI)
- **Configuration Reference**: See `src/config/settings.py` for all available settings
- **Environment Template**: `.env.example` contains a complete list of configuration variables
- **Kubernetes Secrets**: `k8s/secrets.yaml.example` shows the template for production secrets

## Contributing

We welcome contributions to this project:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to your branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Quick Links

- **MLflow Tracking**: http://localhost:5000
- **Airflow UI**: http://localhost:8080
- **Grafana Dashboards**: http://localhost:3000
- **MinIO Console**: http://localhost:9001

---

## Current Development Phase

**Active Phase**: Phase 2 - Production Deployment

**Recently Completed** (January 2025):
- Configuration Management System (Phase 1)
  - Removed all hardcoded credentials from 11 files
  - Implemented environment-based configuration with Pydantic
  - Created Kubernetes secrets templates
  - Documented and implemented security best practices

**Currently Working On**:
- Creating Kubernetes deployment manifests for the API
- Setting up production inference pipeline
- Configuring CI/CD pipeline

**Coming Next**:
- Building unit testing infrastructure
- Integrating monitoring and observability tools
- Deploying the API to production

**Project Health**: The core ML training pipeline is operational and production-ready. The remaining 35% of work focuses on deployment infrastructure, testing, and production operations tooling.

For detailed progress tracking and task management, see the project's issues and pull requests on GitHub.
