# Production ML Infrastructure Boilerplate

**A production-ready MLOps boilerplate that takes ML models from training to production serving with monitoring and auto-scaling.**

[![Docker](https://img.shields.io/badge/Docker-Ready-blue)](https://www.docker.com/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-Ready-326CE5)](https://kubernetes.io/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

---

## 🎯 For Data Scientists

### What You Can Use Today

**1. Complete ML Infrastructure (5 Minutes Setup)**
```bash
docker-compose up -d
```

You get a full production-ready stack:
- **MLflow** - Track experiments, version models
- **MinIO** - Store model artifacts (S3-compatible)
- **PostgreSQL** - Store training data
- **Redis** - Cache features for fast inference
- **API** - Serve predictions via REST
- **Monitoring** - Prometheus + Grafana dashboards

**2. Train & Deploy Your Models**
```python
# Train your model (scikit-learn, LightGBM, XGBoost)
model = train_your_model(X, y)

# Register in MLflow
mlflow.sklearn.log_model(model, "model")

# Promote to Production
# → API automatically loads it and starts serving predictions
```

**3. Access Your Services**
- **API Docs**: http://localhost:8000/docs - Interactive prediction API
- **MLflow UI**: http://localhost:5001 - View experiments and models
- **Grafana**: http://localhost:3000 - Metrics dashboards (admin/admin)
- **Prometheus**: http://localhost:9090 - Raw metrics

**4. Make Predictions**
```bash
# Health check
curl http://localhost:8000/health

# Get predictions
curl -X POST "http://localhost:8000/predict/BTCUSDT" \
  -H "Content-Type: application/json" \
  -d '{"tasks": ["return_1step", "direction_4step"]}'
```

---

## 🔧 For ML Engineers

### What's Production-Ready Now

| Component | Status | What It Provides |
|-----------|--------|------------------|
| **Inference API** | ✅ Ready | FastAPI with auto-docs, health checks |
| **Auto-Scaling** | ✅ Ready | HPA scales 2-10 pods (CPU/memory based) |
| **Model Registry** | ✅ Ready | MLflow with experiment tracking |
| **Monitoring** | ✅ Ready | Prometheus metrics + Grafana dashboards |
| **Health Probes** | ✅ Ready | K8s liveness, readiness endpoints |
| **Feature Cache** | ✅ Ready | Redis with 60s TTL |
| **Storage** | ✅ Ready | MinIO (S3-compatible) for artifacts |
| **K8s Manifests** | ✅ Ready | Deployment, Service, Ingress, HPA |
| **Config Management** | ✅ Ready | Pydantic settings with env vars |

### Architecture

```
User Request
    ↓
Kubernetes Ingress (Load Balancer + SSL)
    ↓
Service → API Pods (2-10, auto-scaling)
    ↓
    ├─→ MLflow Registry (load models)
    ├─→ Redis Cache (feature caching)
    ├─→ MinIO/S3 (model artifacts)
    └─→ Prometheus (export metrics)
         ↓
    Grafana Dashboards
```

### API Capabilities

**Endpoints Ready to Use:**
- `GET /health` - Detailed health with model status
- `GET /live` - K8s liveness probe
- `GET /ready` - K8s readiness probe (checks if models loaded)
- `GET /tasks` - List all available prediction tasks
- `GET /models` - List all loaded models
- `POST /predict/{symbol}` - Multi-task predictions
- `POST /predict/batch` - Batch predictions
- `GET /metrics` - Prometheus metrics endpoint

**Built-in Monitoring:**
- HTTP request metrics (count, duration, status)
- Prediction metrics (count, latency by task)
- Model metrics (loaded models, loading time)
- System metrics (CPU, memory, GC)

---

## 🚀 Quick Start

### Local Development (Docker Compose)

```bash
# 1. Clone repository
git clone <repo-url>
cd ml-eng-with-ops

# 2. Start all services
docker-compose up -d

# 3. Check status
docker-compose ps

# 4. Test API
curl http://localhost:8000/health
```

### Production Deployment (Kubernetes)

```bash
# 1. Apply manifests
kubectl apply -f k8s/

# 2. Check deployment
kubectl get pods
kubectl get hpa

# 3. Access API
kubectl port-forward svc/ml-inference-api 8000:8000
```

See [QUICK_START.md](QUICK_START.md) for detailed deployment guide.

---

## 🎨 Customizing for Your Use Case

This boilerplate includes a cryptocurrency prediction example, but you can adapt it to any ML problem.

### Step 1: Define Your Tasks (5 minutes)

Edit `dags/inference_feature_pipeline.py`:

```python
INFERENCE_TASKS = {
    'your_task_name': {
        'type': 'regression',  # or 'classification_binary', 'classification_multi'
        'description': 'What this task predicts'
    },
    # Add more tasks...
}
```

### Step 2: Feature Engineering (1-2 hours)

Edit `dags/feature_eng.py` to create features from your raw data:

```python
def engineer_features(df):
    # Replace crypto technical indicators with your domain features:
    # - NLP: TF-IDF, embeddings, sentiment scores
    # - Images: CNN features, ResNet embeddings
    # - Tabular: aggregations, one-hot encoding, feature crosses
    # - Time series: lags, rolling windows, seasonality features

    return df
```

### Step 3: Configure Data Source (15 minutes)

Update `.env.development`:

```bash
# Your database
DB_HOST=your-database-host
DB_NAME=your_database_name

# Your entities (replace crypto symbols with your entities)
BINANCE_SYMBOLS='["ENTITY1","ENTITY2","ENTITY3"]'
# Examples: customer IDs, product SKUs, sensor IDs, user IDs
```

### Step 4: Train Models

Use your existing training code. The boilerplate supports:
- Scikit-learn models
- LightGBM / XGBoost
- PyTorch / TensorFlow (coming soon)
- Custom models (if MLflow-compatible)

```python
# Your training code stays mostly the same
model = your_training_function(X_train, y_train)

# Register in MLflow (infrastructure handles the rest)
mlflow.sklearn.log_model(model, "model")
```

**The infrastructure (API, monitoring, deployment) works without changes.**

---

## 📚 Use Cases

This boilerplate has been adapted for:

**Classification:**
- Customer churn prediction
- Fraud detection
- Sentiment analysis
- Spam detection
- Image classification

**Regression:**
- Demand forecasting
- Price prediction
- Sales forecasting
- Resource usage prediction

**Time Series:**
- Stock/crypto prediction
- Sensor data forecasting
- Energy consumption
- Traffic prediction

**Other:**
- Recommendation systems
- Anomaly detection
- Multi-task learning

---

## 🔮 Future Roadmap

### What's Coming Next

**Authentication & Security**
- JWT/OAuth2 authentication
- API key management
- Rate limiting per client
- Request signing

**Advanced ML Capabilities**
- A/B testing framework
- Shadow deployments
- Feature store integration (Feast)
- Online learning support
- Model drift detection (Evidently AI)
- Multi-model serving

**Developer Experience**
- Automated testing (pytest + CI/CD)
- Pre-commit hooks (linting, formatting)
- GitHub Actions workflows
- Dev container support

**Production Features**
- Batch prediction jobs
- Distributed tracing (OpenTelemetry)
- Advanced monitoring (SLIs, SLOs)
- Canary releases
- Automatic rollback

**Infrastructure**
- Terraform modules
- Helm charts
- Multi-cloud templates
- Service mesh integration (Istio)

---

## 📊 Monitoring & Observability

### Metrics Available Now

**HTTP Metrics:**
- Request count by endpoint
- Response latency (P50, P95, P99)
- Status code distribution
- Concurrent requests

**Model Metrics:**
- Predictions per second
- Prediction latency by task
- Loaded models count
- Model loading duration

**System Metrics:**
- CPU & memory usage
- Garbage collection stats
- Process information

### Dashboards

Grafana includes pre-configured dashboards for:
- API performance overview
- Model serving statistics
- Resource utilization
- Error rates and alerts

### Health Checks

| Endpoint | Purpose | K8s Usage |
|----------|---------|-----------|
| `/live` | Process is running | Liveness Probe |
| `/ready` | Can serve traffic | Readiness Probe |
| `/health` | Detailed status | Manual checks |

---

## ⚙️ Configuration

### Environment-Based Settings

The boilerplate uses Pydantic for type-safe configuration:

```python
from src.config import get_settings

settings = get_settings()

# Access configuration
db_config = settings.database.get_connection_dict()
mlflow_uri = settings.mlflow.tracking_uri
api_port = settings.api.port
```

### Configuration Classes

| Class | Env Prefix | Purpose |
|-------|-----------|---------|
| `DatabaseConfig` | `DB_` | PostgreSQL connection |
| `MinIOConfig` | `MINIO_` | S3 storage |
| `RedisConfig` | `REDIS_` | Feature cache |
| `MLflowConfig` | `MLFLOW_` | Model registry |
| `APIConfig` | `API_` | API server settings |
| `MonitoringConfig` | `MONITORING_` | Prometheus metrics |

### Environment Files

```
.env.example       # Template (commit this)
.env.development   # Local dev (gitignored)
.env.production    # Production (gitignored)
```

---

## 📁 Project Structure

```
.
├── app/                          # Inference API
│   ├── production_api.py         # FastAPI application
│   ├── requirements.txt          # API dependencies
│   └── Dockerfile               # Container image
│
├── dags/                         # ML Pipeline Logic
│   ├── model_training.py         # Model training
│   ├── feature_eng.py            # Feature engineering
│   ├── inference_feature_pipeline.py  # Inference logic
│   └── data_versioning.py        # DVC integration
│
├── k8s/                          # Kubernetes Manifests
│   ├── api-deployment.yaml       # Pod specification
│   ├── api-service.yaml          # Service definition
│   ├── api-hpa.yaml             # Auto-scaling rules
│   ├── api-ingress.yaml         # External access
│   ├── api-configmap.yaml       # Configuration
│   └── api-servicemonitor.yaml  # Prometheus scraping
│
├── src/config/                   # Configuration Management
│   └── settings.py              # Pydantic settings
│
├── monitoring/                   # Monitoring Stack
│   ├── prometheus.yml           # Prometheus config
│   └── grafana/                 # Grafana dashboards
│
├── docker-compose.yml           # Local development
├── .env.example                 # Config template
└── README.md                    # This file
```

---

## 🐛 Troubleshooting

### API Returns 503 "No models loaded"

**Expected behavior** - The API waits for models to be registered in MLflow.

**Solution:**
1. Train a model
2. Register it in MLflow
3. Promote to "Production" stage
4. API will auto-load it

### Port Conflicts

**Problem:** Port already in use (e.g., 8000, 5001)

**Solution:** Edit `docker-compose.yml` and change port mappings:
```yaml
ports:
  - "8001:8000"  # Map host 8001 to container 8000
```

### Services Not Starting

```bash
# Check logs
docker-compose logs api
docker-compose logs mlflow

# Restart services
docker-compose restart

# Rebuild if needed
docker-compose up -d --build
```

### Memory Issues

**Problem:** Services crash with OOM errors

**Solution:** Increase Docker memory limit
- Docker Desktop → Settings → Resources → Memory (increase to 6-8GB)

---

## 🤝 Contributing

Contributions welcome! Help improve this boilerplate for the ML community.

**How to contribute:**
1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Make your changes
4. Test: `./test.sh`
5. Submit a Pull Request

**Areas needing help:**
- Additional model frameworks
- More monitoring dashboards
- Cloud provider examples
- Testing infrastructure
- Documentation improvements

---

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.

---

## 🔗 Built With

- **[FastAPI](https://fastapi.tiangolo.com/)** - Modern web framework for APIs
- **[MLflow](https://mlflow.org/)** - ML lifecycle management
- **[Prometheus](https://prometheus.io/)** - Monitoring and alerting
- **[Grafana](https://grafana.com/)** - Visualization dashboards
- **[Kubernetes](https://kubernetes.io/)** - Container orchestration
- **[Redis](https://redis.io/)** - In-memory caching
- **[MinIO](https://min.io/)** - S3-compatible storage

---

**Accelerate your ML team from model to production API**
