# Crypto ML Pipeline

Production-grade ML pipeline for cryptocurrency price prediction with multi-task learning, featuring enterprise MLOps infrastructure including Airflow orchestration, DVC data versioning, MLflow model registry, and comprehensive monitoring.

## 🎯 Features

- **Multi-Task Learning**: 7 prediction tasks (price returns, direction, volatility)
- **Airflow Orchestration**: Automated data quality, feature engineering, validation, versioning, and model training
- **DVC Data Versioning**: Git-based data versioning with S3/MinIO backend
- **MLflow Model Registry**: Experiment tracking and stage-based model promotion (Training → Staging → Production)
- **MinIO Storage**: S3-compatible artifact storage for models and features
- **Comprehensive Monitoring**: Prometheus metrics + Grafana dashboards
- **Production API**: FastAPI service for real-time predictions
- **Secure Configuration**: Environment-based secrets management

## 📁 Project Structure

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
├── .env.example                # Environment template (COMMIT)
├── .env.development            # Development config (DO NOT COMMIT)
├── .env.production             # Production config (DO NOT COMMIT)
├── Dockerfile                  # Airflow container
├── requirements.txt            # Pipeline dependencies
└── README.md                   # This file
```

## 🚀 Quick Start

### 1. Clone & Install

```bash
git clone https://github.com/yourusername/ml-eng-with-ops.git
cd ml-eng-with-ops

# Install dependencies
pip install -r requirements.txt
```

### 2. Configuration Setup

**For Local Development:**

```bash
# Copy environment template
cp .env.example .env.development

# Edit with your local credentials
nano .env.development

# Set environment
export ENVIRONMENT=development
```

**Key variables to configure:**
```bash
# Database
DB_HOST=localhost
DB_PORT=5432
DB_USER=your_user
DB_PASSWORD=your_password  # NEVER commit this!

# MinIO
MINIO_ENDPOINT=minio:9000
MINIO_ACCESS_KEY=admin
MINIO_SECRET_KEY=your_secret  # NEVER commit this!

# See .env.example for complete list
```

**For Production (Kubernetes):**

```bash
# Create secrets file
cp k8s/secrets.yaml.example k8s/secrets.yaml

# Encode secrets
echo -n "your_password" | base64

# Fill in base64 values in k8s/secrets.yaml
# Apply to cluster
kubectl apply -f k8s/secrets.yaml
```

### 3. Build Docker Images

```bash
# Airflow image
docker build -t custom-airflow:0.0.4 .

# API image
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

### 5. Run the Pipeline

**Access Airflow UI:**
```bash
kubectl port-forward svc/airflow-webserver 8080:8080
# Visit http://localhost:8080 (default: admin/admin123)
```

**Trigger the DAG:**
- Navigate to DAGs → `crypto_ml_pipeline` → Trigger

**Monitor Progress:**
- Airflow UI: Task execution logs
- MLflow: http://localhost:5000 (experiments & models)
- Grafana: http://localhost:3000 (metrics dashboards)

## 📊 ML Pipeline Architecture

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

| Task | Type | Horizon | Description |
|------|------|---------|-------------|
| `return_1step` | Regression | 15 min | Short-term price return |
| `return_4step` | Regression | 1 hour | Medium-term price return |
| `return_16step` | Regression | 4 hours | Long-term price return |
| `direction_4step` | Binary Classification | 1 hour | Up/Down direction |
| `direction_multi_4step` | Multi-class (5) | 1 hour | Trend classification |
| `volatility_4step` | Regression | 1 hour | Volatility prediction |
| `vol_regime_4step` | Multi-class (3) | 1 hour | Volatility regime |

### Supported Symbols
BTCUSDT, ETHUSDT, BNBUSDT, ADAUSDT, SOLUSDT, XRPUSDT, DOTUSDT, AVAXUSDT, MATICUSDT, LINKUSDT

## 🔧 Configuration Management

### Configuration Structure

The project uses **Pydantic Settings** for type-safe, environment-based configuration:

```python
from src.config import get_settings

settings = get_settings()

# Database connection
db_config = settings.database.get_connection_dict()

# MinIO client
minio_config = settings.minio.get_client_config()

# Trading symbols
symbols = settings.binance.symbols
```

### Available Configuration Classes

| Class | Environment Prefix | Purpose |
|-------|-------------------|---------|
| `DatabaseConfig` | `DB_` | PostgreSQL connection |
| `MinIOConfig` | `MINIO_` | MinIO/S3 storage |
| `RedisConfig` | `REDIS_` | Redis cache |
| `MLflowConfig` | `MLFLOW_` | MLflow tracking |
| `DVCConfig` | `DVC_` | DVC versioning |
| `BinanceConfig` | `BINANCE_` | Binance API |
| `APIConfig` | `API_` | FastAPI server |
| `MonitoringConfig` | `MONITORING_` | Prometheus/Sentry |

### Environment Selection

The system automatically loads the correct environment file:

```bash
# Development
export ENVIRONMENT=development  # Loads .env.development

# Staging
export ENVIRONMENT=staging      # Loads .env.staging

# Production
export ENVIRONMENT=production   # Loads .env.production or K8s secrets
```

## 🔐 Security Best Practices

### ✅ DO
- Use environment variables for all secrets
- Use Kubernetes secrets in production
- Commit `.env.example` (template without real values)
- Set file permissions to 600 for .env files
- Rotate secrets regularly
- Use different secrets for dev/staging/prod

### ❌ DON'T
- Never commit `.env.development`, `.env.staging`, `.env.production`
- Never commit `k8s/secrets.yaml` (only `.example`)
- Never hardcode credentials in code
- Never share .env files via chat/email
- Never log sensitive values

## 📡 Production API

### Start API Server

```bash
cd app
uvicorn production_api:app --host 0.0.0.0 --port 8000
```

### API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Service health check |
| `/tasks` | GET | List available prediction tasks |
| `/models` | GET | List loaded models |
| `/predict/{symbol}` | POST | Multi-task predictions |
| `/predict/batch` | POST | Batch predictions |
| `/predict/{symbol}/task/{task}` | GET | Single task prediction |
| `/models/reload` | POST | Reload models from MLflow |

### Example Request

```bash
# Get predictions for BTCUSDT
curl -X POST "http://localhost:8000/predict/BTCUSDT" \
  -H "Content-Type: application/json" \
  -d '{"tasks": ["return_1step", "direction_4step"]}'
```

### Example Response

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

## 📈 Monitoring & Observability

### Prometheus Metrics

The pipeline exports custom metrics:
- `data_quality_score` - Data quality assessment scores
- `feature_count` - Number of features generated
- `model_training_duration` - Training time per model
- `model_performance_rmse` - Model RMSE metrics
- `validation_failures` - Data validation failures

### Grafana Dashboards

Pre-configured dashboards available in `ml-dashboard-configmap.yaml`:
- Pipeline execution overview
- Data quality trends
- Model performance comparison
- Validation failures tracking

### Logs

```bash
# Airflow task logs
kubectl logs -f <airflow-pod> -n airflow

# API logs
kubectl logs -f <api-pod> -n ml-pipeline
```

## 🧪 Testing

```bash
# Run tests (when implemented)
pytest tests/

# Test configuration loading
python -c "from src.config import get_settings; print(get_settings().database.host)"

# Test database connection
python -c "import psycopg2; from src.config import get_settings; psycopg2.connect(**get_settings().database.get_connection_dict())"
```

## 🐛 Troubleshooting

### Configuration Issues

**Problem:** "No module named 'src'"
**Solution:** Ensure you're in the project root or path is added correctly

**Problem:** "DB_PASSWORD field required"
**Solution:** Create `.env.development` with required variables

### Kubernetes Issues

**Problem:** Pod failing to start
**Solution:**
```bash
# Check secrets exist
kubectl get secrets -n ml-pipeline

# Check pod environment
kubectl exec -it <pod> -- env | grep DB_

# Check logs
kubectl logs <pod> -n ml-pipeline
```

### MLflow Issues

**Problem:** Models not registering
**Solution:** Check MLflow tracking URI and ensure service is accessible

## 🗺️ Roadmap

### Phase 1: Production Blockers (Completed ✅)
- [x] Configuration management system
- [x] Environment-based secrets
- [x] Kubernetes secrets template
- [ ] CI/CD pipeline (GitHub Actions)
- [ ] Unit testing infrastructure
- [ ] Kubernetes deployment manifests

### Phase 2: Production Readiness
- [ ] Error handling refactor
- [ ] API enhancements (metrics, rate limiting)
- [ ] Monitoring instrumentation
- [ ] Structured logging

### Phase 3: Code Quality
- [ ] Code restructuring (modular packages)
- [ ] Type hints & linting
- [ ] Pre-commit hooks
- [ ] Comprehensive documentation

### Phase 4: Advanced MLOps
- [ ] Model drift detection
- [ ] A/B testing framework
- [ ] Feature store integration
- [ ] AutoML pipeline

## 📚 Documentation

- **API Docs**: http://localhost:8000/docs (Swagger UI)
- **Configuration**: See `src/config/settings.py` for all settings
- **Environment Template**: `.env.example` - Complete variable reference
- **K8s Secrets**: `k8s/secrets.yaml.example` - Production secrets template

## 🤝 Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.

## 🔗 Links

- **MLflow**: http://localhost:5000
- **Airflow**: http://localhost:8080
- **Grafana**: http://localhost:3000
- **MinIO Console**: http://localhost:9001

---

**Status**: ✅ Configuration Management Complete | 🚧 Testing & Deployment In Progress

For detailed refactoring progress, see project issues and pull requests.
