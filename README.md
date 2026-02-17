# K8s App Shipping Engine

> **Template: The "K8s App Shipping" Engine**
> Stack: **Docker + Kubernetes + Helm/Kustomize + GitHub Actions** on GCP/GKE

---

## Overview

Every new microservice you build drops into this template and gets:

- **Multi-stage Docker build** — lean production image with non-root user, read-only FS
- **Kustomize overlays** — single base manifest, env-specific patches (dev/prod)
- **Helm chart** — alternative to Kustomize if you prefer templating
- **GitHub Actions pipeline** — test → build → Trivy scan → push to GCR → deploy dev → gate → deploy prod
- **Health endpoints** — `/healthz` (liveness), `/readyz` (readiness), `/metrics` (Prometheus)
- **Graceful shutdown** — SIGTERM handler drains connections before pod terminates
- **HPA + PDB** — auto-scales on CPU/memory, maintains minimum availability during disruptions

---

## Folder Structure

```
.
├── .github/workflows/
│   └── build-and-deploy.yml   # Full CI/CD pipeline
├── app/
│   ├── src/server.js          # Express app with health + metrics endpoints
│   └── package.json
├── docker/
│   ├── Dockerfile             # Multi-stage build (deps → build → runtime)
│   └── .dockerignore          # Keeps image lean (excludes infra, tests, docs)
├── k8s/
│   ├── base/                  # Deployment, Service, HPA, PDB, ConfigMap
│   └── overlays/
│       ├── dev/               # 1 replica, debug logging, smaller resources
│       └── prod/              # 3+ replicas, HA, stricter limits
├── helm/
│   ├── Chart.yaml
│   ├── values.yaml            # Defaults (overridden per env with --values flag)
│   └── templates/             # Add your Helm templates here
├── scripts/
│   └── health-check.sh        # Post-deploy verification (rollout + HTTP + replicas)
└── README.md
```

---

## Initial Setup

### 1. Rename `my-service` throughout

```bash
# Quick find-replace
SERVICE_NAME="payment-service"   # ← your service name
find . -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.js" -o -name "*.json" \) \
  -exec sed -i "s/my-service/${SERVICE_NAME}/g" {} +
```

### 2. Update GCR image references

Edit `k8s/overlays/dev/kustomization.yaml` and `prod/kustomization.yaml`:
```yaml
images:
  - name: my-service
    newName: gcr.io/YOUR_PROJECT_ID/your-service-name
```

### 3. Set GitHub Secrets

| Secret | Value |
|--------|-------|
| `GCP_PROJECT_ID` | Your GCP project ID |
| `GCP_WIF_PROVIDER` | Workload Identity Federation provider |
| `GCP_SA_EMAIL` | Terraform/deploy service account email |
| `GCP_WIF_PROVIDER_PROD` | Prod WIF provider |
| `GCP_SA_EMAIL_PROD` | Prod service account |
| `DATADOG_API_KEY` | For deployment event annotations |

---

## CI/CD Pipeline Flow

```
PR opened
  └─ Test (npm test)
  └─ Lint (eslint)

Merge to develop / main
  └─ Build multi-stage Docker image (cached layers via GitHub Actions cache)
  └─ Tag image with short Git SHA (e.g. gcr.io/project/service:a1b2c3d4)
  └─ Push :sha-tag + :latest to GCR
  └─ Trivy vulnerability scan (blocks on CRITICAL CVEs)
  └─ Deploy to dev (kustomize overlay → kubectl apply)
  └─ Run health-check.sh (rollout status + HTTP /healthz)

Merge to main only, after dev deploy
  └─ [Manual approval gate via GitHub Environment]
  └─ Deploy to prod (prod overlay)
  └─ Run health-check.sh
  └─ Annotate Datadog with deployment event
```

---

## Local Development

```bash
# Run the app locally
cd app && npm install && npm start

# Build and run with Docker
docker build -f docker/Dockerfile -t my-service:local .
docker run -p 3000:3000 my-service:local

# Test health endpoints
curl http://localhost:3000/healthz
curl http://localhost:3000/readyz
curl http://localhost:3000/metrics

# Preview kustomize output without applying
kubectl kustomize k8s/overlays/dev

# Deploy manually to dev
cd k8s/overlays/dev
kustomize edit set image my-service=gcr.io/my-project/my-service:abc1234
kustomize build . | kubectl apply -f -
```

---

## Switching Runtimes

This template ships with Node.js. To use Python, Go, or Java:

**Python (FastAPI):**
```dockerfile
FROM python:3.12-slim AS runtime
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app/ .
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "3000"]
```

**Go:**
```dockerfile
FROM golang:1.22-alpine AS build
WORKDIR /app
COPY go.* ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o server ./cmd/server

FROM scratch AS runtime
COPY --from=build /app/server /server
CMD ["/server"]
```

---

## Security Decisions

| Decision | Reason |
|----------|--------|
| Non-root user (`runAsUser: 1000`) | Prevents container breakout privilege escalation |
| Read-only root filesystem | Detects unexpected file writes (malware, misconfigs) |
| Drop ALL capabilities | Least-privilege; add back only what you need |
| No `:latest` tag in prod | Immutable deploys — exact SHA pinning |
| Trivy scan in CI | Blocks known CRITICAL CVEs before they reach the cluster |
| `topologySpreadConstraints` | Pods spread across zones — survives a zone outage |
