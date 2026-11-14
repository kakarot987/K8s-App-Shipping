# K8s App Shipping Engine

A **sample** Node.js microservice with a Docker image, Kustomize environments, a working starter Helm chart, and a GitHub Actions pipeline. This is a template: GCP credentials, clusters, Artifact Registry, environment approvals, and service-specific dependency checks must be configured before production use.

## Included

- Express app with `/healthz`, `/readyz`, and `/metrics` (Prometheus).
- Jest/Supertest endpoint tests and ESLint checks.
- Multi-stage Docker build with a non-root runtime user and read-only container filesystem in Kubernetes.
- Kustomize base, `dev` and `prod` overlays, plus a separate Helm chart.
- GitHub Actions: test, lint, and Docker image build verification on PRs and pushes, **without cloud credentials**. Publishing and deploying to GCP on pushes are separately opt-in. Production deployment requires a second opt-in and should use a protected `prod` environment.

## Directory layout

```text
.github/workflows/build-and-deploy.yml
app/src/server.js
app/test/server.test.js
app/.eslintrc.cjs
app/.dockerignore
app/package.json
app/package-lock.json
docker/Dockerfile
k8s/base/
k8s/overlays/dev/
k8s/overlays/prod/
helm/Chart.yaml
helm/values.yaml
helm/templates/
scripts/health-check.sh
```

## Local development

Requires Node.js 20+.

```bash
npm ci --prefix app
npm run lint --prefix app
npm test --prefix app
npm start --prefix app
```

From a second terminal:

```bash
curl --fail http://localhost:3000/healthz
curl --fail http://localhost:3000/readyz
curl --fail http://localhost:3000/metrics
```

The sample has **no database or cache dependency**. `/readyz` returns HTTP 503 during shutdown, otherwise 200. Extend it with dependency checks when adding real dependencies. The health endpoints do not prove a real workload's downstream services are healthy.

## Docker

Build using `app/` as the **context** (not the repository root):

```bash
docker build -f docker/Dockerfile -t my-service:local ./app
docker run --rm -p 3000:3000 my-service:local
```

The ignore file is `app/.dockerignore`, because Docker reads it from the context root. The production image contains app runtime dependencies and source, not test dependencies.

## Kubernetes with Kustomize

Preview the deployment (requires `kubectl` with Kustomize support or the standalone `kustomize` CLI):

```bash
kubectl kustomize k8s/overlays/dev
kubectl kustomize k8s/overlays/prod
```

The dev Deployment is **`dev-my-service` in namespace `dev`**. The prod Deployment is **`my-service` in namespace `prod`**. The dev HPA scales from 1 to 3, and the prod HPA from 3 to 20. HPA requires the Kubernetes Metrics Server (or an equivalent metrics API). A 1-replica dev environment and its PodDisruptionBudget are not designed for high availability.

For a manual dev deployment, configure the correct image first:

```bash
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -
cd k8s/overlays/dev
kustomize edit set image my-service=us-central1-docker.pkg.dev/PROJECT_ID/services/my-service:IMAGE_TAG
kustomize build . | kubectl apply -f -
cd ../../..
kubectl rollout status deployment/dev-my-service -n dev
bash scripts/health-check.sh dev-my-service dev
```

Replace `PROJECT_ID` and `IMAGE_TAG`. The command `kustomize edit set image` changes the local overlay; reset/review that change before committing. Namespace creation requires appropriate cluster permissions. The health-check script reads the Deployment's `app` selector rather than assuming the Deployment name is a pod label; it **fails** if no running pod can be checked.

### Database credentials

No database is used by this sample; there is no `DB_PASSWORD` variable or required Secret. When introducing a database, provision a real Kubernetes Secret securely via your deployment platform/secret manager and reference its key in the Deployment. Do not commit real passwords or Secret values into Git.

### Workload Identity

The base ServiceAccount does not impersonate a GCP service account. Add the `iam.gke.io/gcp-service-account` annotation and corresponding IAM bindings if your application needs Workload Identity. The GitHub Actions deploy identity is configured separately through Workload Identity Federation.

## Helm (alternative to Kustomize)

The starter chart provides a Deployment, Service, ConfigMap, ServiceAccount, HPA, PDB, and optional Ingress. Helm is an alternative deployment path and is **not** what the GitHub Actions workflow currently deploys.

```bash
helm lint ./helm
helm template demo ./helm --namespace dev \
  --set image.repository=us-central1-docker.pkg.dev/PROJECT_ID/services/my-service \
  --set image.tag=IMAGE_TAG
# Only after configuring cluster access:
helm upgrade --install demo ./helm --namespace dev --create-namespace \
  --set image.repository=us-central1-docker.pkg.dev/PROJECT_ID/services/my-service \
  --set image.tag=IMAGE_TAG
```

To run one replica without autoscaling, set `autoscaling.enabled=false`, `replicaCount=1`, and `pdb.enabled=false`. Configure ingress and Workload Identity in `helm/values.yaml` or your own override file. Do not deploy with the placeholder image path.

## GitHub Actions setup

By default, CI runs tests and a Docker build but **does not publish or deploy**. To enable Google Cloud publishing and dev deployment, first configure these repository secrets and resources:

| Name | Purpose |
| --- | --- |
| `GCP_PROJECT_ID` | GCP project containing Artifact Registry images |
| `GCP_WIF_PROVIDER` | Workload Identity Federation provider for build and dev |
| `GCP_SA_EMAIL` | GCP service account for build and dev operations |
| `GCP_WIF_PROVIDER_PROD` | Prod federation provider |
| `GCP_SA_EMAIL_PROD` | GCP service account for prod deployments |
| `DATADOG_API_KEY` | Optional Datadog deployment-event annotation |

Then open **Settings → Secrets and variables → Actions → Variables** and create repository variable `GCP_DEPLOY_ENABLED` with value `true`. Until enabled, the `Publish to Artifact Registry` and deployment jobs intentionally show as **skipped** while tests and Docker image checks run. The publishing job fails with a clear error if the required repository secrets are missing. Do not set this variable until GCP Workload Identity Federation, Artifact Registry and GKE are ready.

To additionally allow production deployment from `main`, set `GCP_PROD_DEPLOY_ENABLED=true` and supply production federation/service-account secrets. These may be scoped to the GitHub `prod` environment. Configure **required reviewers** for that environment before enabling production deployment; an environment name alone does not enforce approval.

Create a Docker Artifact Registry repository named **`services`** in **`us-central1`** (or update `GAR_REPOSITORY`, `GAR_REGISTRY` and `GCP_REGION` in the workflow). Grant the build identity Artifact Registry writer access and the deployment identities the required GKE/Kubernetes RBAC permissions. Ensure nodes can pull the Artifact Registry image. Create or configure `dev-gke-cluster` and `prod-gke-cluster`, or replace the workflow values. Configure GitHub `dev` and `prod` environments; **add required reviewers to `prod`** if a manual approval gate is expected.

On a PR targeting `main`, tests, linting and a local Docker image build run without cloud credentials. On pushes to `develop` or `main`, the same validation runs; **only when `GCP_DEPLOY_ENABLED=true`** does the workflow push `us-central1-docker.pkg.dev/<PROJECT_ID>/services/my-service:<short-sha>`, scans for CRITICAL CVEs, deploys the dev overlay and checks rollout and HTTP health. On `main`, prod follows after dev succeeds **only when `GCP_PROD_DEPLOY_ENABLED=true`**, and after any configured environment approval. Builds also publish `:latest` for convenience; cluster deployments use the immutable short-SHA image tag.

**Validation status:** This template requires a real, successful GitHub Actions run plus cloud infrastructure and secrets to claim end-to-end deployment readiness. Local syntax checks alone do not validate GKE authentication, deployment permissions, image pulling, vulnerability scan results, or live health checks.

## Security notes

The Kubernetes container uses non-root UID 1000, drops Linux capabilities, prevents privilege escalation, and mounts `/tmp` as writable while the root filesystem remains read-only. Default readiness only tracks shutdown state; add real dependency checks before marketing this as a production-ready service. Production resilience also depends on multi-zone cluster capacity, replica and PDB settings, metrics availability, and operational alerting.
