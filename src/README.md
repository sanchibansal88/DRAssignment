# Multi-Region DR Platform (Azure)

This repo contains Terraform, Kubernetes manifests, Helm values, and automation scripts for a multi-region (active/passive) disaster recovery design that protects a stateless microservice stack, a managed PostgreSQL database, and a multi-user Jupyter-like notebook hub. Azure is the cloud of choice. 

## Recovery Objectives
- **Recovery Point Objective (RPO)**: < 1 minute — asynchronous Azure Database for PostgreSQL geo-replication plus a scripted write-freeze keep committed data loss to roughly the replication lag (typically seconds).
- **Recovery Time Objective (RTO)**: ≤ 15 minutes — automated failover (`scripts/failover_app.sh`) promotes the DR database, patches secrets, scales services, and flips JupyterHub/microservices traffic with minimal manual steps.

## Architecture at a Glance
- **Regions**: Primary = `west us3`, DR = `uaenorth` (override in Terraform variables).
- **Networking**: Regional VNets with delegated subnets for AKS. Peering or Azure Private Link is recommended when connecting to managed services.
- **Kubernetes**: Two AKS clusters (system-assigned identities, Azure CNI) host microservices, notebook hub.
- **Database**: Azure Database for PostgreSQL Flexible Server primary + geo-replica using async WAL shipping.
- **Notebook Hub**: Helm-based deployment of JupyterHub with Azure Files (ZRS) backed PVCs so user homes persist cross-region. Hub metadata lives on PostgreSQL so the DR cluster can mount a promoted replica.
- **Automation**: Bash helpers wrap Terraform, kubectl, and Helm for reproducible deploy, failover, and cleanup flows.

```
Users ─▶ Load balancer
             │
             ├──▶ Primary Region (AKS + Postgres primary + notebooks)
             │       │
             │       └── Azure Files (ZRS) for notebook homes
             │
             └──▶ DR Region (AKS passive + Postgres replica + standby notebooks)
                     │
                     └── Azure Files (RA-GRS) replicated share
```

## Repository Layout
| Path | Description |
| --- | --- |
| `terraform/` | AKS, VNet, and Azure Database for PostgreSQL infrastructure. Modular code for reuse. |
| `k8s/microservices/` | Namespace manifest + legacy raw specs (Helm chart is now the canonical deployment). |
| `k8s/jupyterhub/` | Namespace manifest plus Helm values overrides (primary + DR) for JupyterHub. |
| `services/` | Flask source code + Dockerfile for `frontend-api` (business logic + ingestion helpers). |
| `helm/frontend-api` | Helm chart that packages the frontend API Deployment/Service/ConfigMap. |
| `helm/microservices` | Helm chart for deploying the API, business-logic, and data-ingestion services together. |
| `scripts/` | Automation (`deploy_primary.sh`, `deploy_dr.sh`, `failover_app.sh`, `cleanup.sh`). |

### Application Service
`frontend-api` exposes `POST /users`, validates payloads, runs internal business logic (`services/frontend-api/business_logic.py`), and persists the data through the ingestion helpers (`services/frontend-api/ingest.py`) directly into PostgreSQL.

Build and push the container images before deploying:
Terraform now provisions an Azure Container Registry (ACR) in the primary region and grants both AKS clusters the `AcrPull` role so they can pull workload images. After `terraform apply`, grab the outputs and push the freshly built image:
```bash
export REGISTRY_NAME=$(terraform -chdir=terraform output -raw container_registry_name)
export REGISTRY_LOGIN_SERVER=$(terraform -chdir=terraform output -raw container_registry_login_server)

az acr login --name "$REGISTRY_NAME"
docker build -t $REGISTRY_LOGIN_SERVER/dr-frontend-api:latest services/frontend-api
docker push $REGISTRY_LOGIN_SERVER/dr-frontend-api:latest
```
Update the image settings in `helm/frontend-api/values.yaml` (or pass `--set image.repository=...`) if you decide to publish under a different path/registry.

### Deploying with Helm
The `helm/frontend-api` chart encapsulates the Kubernetes objects that were previously applied with raw manifests. Before installing, ensure the `database-credentials` secret exists in the target namespace (or override `database.existingSecret`).

```bash
# create database-credentials secret here (via SealedSecrets, AKV CSI, etc.)

helm upgrade --install frontend-api ./helm/frontend-api \
  --namespace app-platform \
  --create-namespace \
  --set image.repository=app \
  --set image.tag=latest \
  --set config.serviceMode=active \
  --set config.jupyterHubBaseUrl=https://notebooks.example.com
```

For day-to-day development we simply tag the image that was built from this repository
(`docker build -t dr-frontend-api:latest services/frontend-api`) and load it into the target
cluster (`kind load docker-image ...`, `minikube image load ...`, etc.) so the chart can pull it
directly without relying on a remote registry. The automation scripts consume the same chart, so
export `FRONTEND_IMAGE_REPOSITORY`, `FRONTEND_IMAGE_TAG`, `FRONTEND_REPLICA_COUNT`,
`FRONTEND_DR_REPLICA_COUNT`, or `FRONTEND_NAMESPACE` before running them if you need to override the defaults. The optional PostgreSQL Helm releases use `POSTGRES_PRIMARY_RELEASE` and `POSTGRES_DR_RELEASE` env vars for the release names.

Key values:
- `replicaCount`, `resources`: scale knobs for the Deployment.
- `database.*`: secret names/keys for DB connectivity.
- `config.*`: values surfaced in the ConfigMap (`SERVICE_MODE`, `JUPYTERHUB_BASE_URL`).
- `autoScaling.enabled`: enable and configure HPA (extend chart with HPA manifest if desired).

You can integrate the chart with GitOps tools (Argo CD/Flux) for drift-free deployments across regions.

To deploy all three services (API, business logic, data ingestion) together, use the `helm/microservices` chart:

```bash
helm upgrade --install microservices ./helm/microservices \
  --namespace app-platform \
  --set api.image.repository=ghcr.io/<org>/api \
  --set businessLogic.image.repository=ghcr.io/<org>/logic \
  --set dataIngest.image.repository=ghcr.io/<org>/ingest \
  --set secret.name=database-credentials
```

Values allow independent tuning for each Deployment (replicas, resources, env vars) while sharing the same ConfigMap and database secret.

### Optional PostgreSQL StatefulSets (Helm)
The previous raw manifests under `k8s/database/` have been re-packaged as a dedicated Helm chart in `helm/postgres`. Use it when you want an in-cluster PostgreSQL primary/replica for testing or to mirror Azure Flexible Server settings.

```bash
# Primary (writes) cluster
helm upgrade --install primary-postgres ./helm/postgres \
  --namespace app-platform \
  --create-namespace \
  --set mode=primary

# DR replica following either the in-cluster primary or Azure Flexible Server
helm upgrade --install dr-postgres ./helm/postgres \
  --namespace app-platform \
  --create-namespace \
  --set mode=dr \
  --set dr.primaryHost=primary-pg.postgres.database.azure.com
```

The deploy scripts consume the same chart—override `POSTGRES_PRIMARY_RELEASE`, `POSTGRES_DR_RELEASE`, or pass extra `--set` flags through `HELM_EXTRA_ARGS` (if you wrap the scripts) when you need to tweak images, persistence, or secret names.

## Prerequisites
- macOS/Linux shell with `terraform >=1.5`, `az`, `kubectl`, `helm`, and `envsubst` (from GNU `gettext`).
- Azure subscription with at least two enabled regions, AKS + PostgreSQL quotas, and permissions to create resource groups, VNets, and managed identities.
- Local Azure CLI login (`az login`).
- `kubectl` contexts named for each cluster (scripts reference `PRIMARY_KUBE_CONTEXT` and `DR_KUBE_CONTEXT`).
- Secrets stored in Azure Key Vault, HashiCorp Vault, or via SealedSecrets. This repo intentionally provides `*-template.yaml` manifests instead of real secrets.

## Terraform Steps
1. Customize `terraform/variables.tf` or provide a `terraform.tfvars` (recommended) with:
   ```hcl
   project_name            = "dr-microservices"
   postgres_admin_password = "<store in env var TF_VAR_postgres_admin_password>"
   ```
2. Export sensitive values before running scripts:
   ```bash
   export TF_VAR_postgres_admin_password=$(az keyvault secret show ...)
   ```
3. (Optional) Validate: `terraform -chdir=terraform plan`.
4. `scripts/deploy_primary.sh`/`deploy_dr.sh` both run `terraform apply` to keep state in sync—plan will be a no-op if already applied.

Outputs include kubeconfigs, PostgreSQL FQDNs, and the Azure Container Registry coordinates (`container_registry_name`, `container_registry_login_server`) that you will use for `docker build/push`.

## Secret Management Strategy
- Duplicate `k8s/microservices/database-secret-template.yaml` and `k8s/database/postgres-secrets-template.yaml` into your secrets tool (e.g., `kubeseal`, Azure Key Vault CSI driver, or External Secrets Operator).
- Populate:
  - `DATABASE_HOST`, `DATABASE_READ_REPLICA_HOST` with Terraform outputs.
  - `DATABASE_USER/PASSWORD` + `replication-user/password`.
- For JupyterHub, inject `HUB_SERVICE_TOKEN` and `PROXY_SECRET_TOKEN` via CI/CD variables so `envsubst` in the deploy scripts never logs them.

## Deployment Workflow
```bash
export PRIMARY_KUBE_CONTEXT=aks-primary
export DR_KUBE_CONTEXT=aks-dr
export PRIMARY_POSTGRES_FQDN=primary-pg.postgres.database.azure.com
export DR_POSTGRES_FQDN=dr-pg.postgres.database.azure.com
export HUB_SERVICE_TOKEN=$(openssl rand -hex 32)
export PROXY_SECRET_TOKEN=$(openssl rand -hex 32)
```

1. `./scripts/deploy_primary.sh`
   - Runs Terraform (idempotent), installs the optional primary PostgreSQL StatefulSet via `helm/postgres`, and rolls out the `frontend-api` Helm release in active mode (no Kustomize required).
2. `./scripts/deploy_dr.sh`
   - Same Terraform apply, installs the DR PostgreSQL replica via `helm/postgres` (pointing `dr.primaryHost` to the active writer), and installs the same Helm release with `config.serviceMode=standby`.
   - Default replicas are `0` (override with `FRONTEND_DR_REPLICA_COUNT`) so the region is cold but ready. JupyterHub stays up in read-only mode for notebook viewing.
3. Create DNS records so `api.example.com` and `notebooks.example.com` point to the primary Ingress/Public IP (fronted by Traffic Manager/Front Door).

Terraform also linked both AKS kubelet identities to the ACR with the `AcrPull` role, so once you push an image to the registry login server output, the Helm releases can pull it without extra secrets.

### Validating Success
- **Microservices**: `kubectl --context $PRIMARY_KUBE_CONTEXT get deploy -n app-platform` (replicas available). Run smoke tests against `frontend-api` service.
- **Database replication**: From Azure CLI `az postgres flexible-server replica list -g rg-... -n dr-microservices-pg`. On the DR AKS cluster, `kubectl exec -n app-platform statefulset/dr-postgres -- psql -c 'SELECT pg_is_in_recovery();'` should return `t`.
- **JupyterHub**: `helm status jupyterhub -n notebooks --kube-context $PRIMARY_KUBE_CONTEXT`. Access the ingress host and confirm user homes mount the Azure Files share (`df -h /home/jovyan`).

## Simulating Disaster & Failing Over
1. **Trigger**: Run `./scripts/failover_app.sh` after exporting:
   ```bash
   export PRIMARY_POSTGRES_SERVER=dr-microservices-pg
   export DR_POSTGRES_SERVER=dr-microservices-pg-dr
   export PRIMARY_RG=rg-dr-microservices-primary
   export DR_RG=rg-dr-microservices-dr
   ```
2. Script actions:
   - Puts primary cluster into read-only mode and scales workloads to zero.
   - Promotes the Azure PostgreSQL replica (stops replication) and rewrites DB secrets on DR.
   - Marks DR config as active, scales Deployments to 3 replicas, and reconfigures JupyterHub to full read/write mode.
   - Prints the Azure CLI snippet needed to update Traffic Manager/DNS.
3. **Verification**: Run smoke tests, ensure `pg_is_in_recovery()` on DR now returns `f`, and confirm notebooks can execute cells and persist new files.

### Notebook Availability Approach
- User home directories live on Azure Files with ZRS for intra-region resiliency. We enable RA-GRS replication on the storage account and take hourly `az storage share snapshot` copies that can be mounted read-only in the DR region if cross-region recovery is needed before DNS cutover.
- During normal operations, DR JupyterHub remains read-only via the `singleuser.extraEnv.WORKSPACE_MODE` flag. During failover the `failover_app.sh` script flips it back to active so new writes occur on the promoted share.

### Failback (High Level)
1. Restore the original primary by rebuilding AKS or re-running `deploy_primary.sh` if needed.
2. Provision a new PostgreSQL replica sourced from the (now) active DR server (`az postgres flexible-server replica create`).
3. Wait for replication to catch up, then re-enable microservices on the original primary cluster and update DNS back.
4. Run `deploy_dr.sh` again to return the DR region to passive mode.

## Monitoring & Alerting Ideas
| Area | Metric/Probe | Alert |
| --- | --- | --- |
| PostgreSQL | Replication lag (`pg_stat_wal_receiver`), server availability, failed backups | >30s lag, replica disconnected, backup failure |
| AKS workloads | Pod readiness, HPA saturation, node not ready | Pod unavailable >2m, node count below desired |
| Notebooks | JupyterHub API {200, latency}, PVC saturation | /hub/api at >1s, PVC usage >80% |
| Traffic Manager | Endpoint status | Endpoint degraded triggers DR warm-up |

Log aggregation and alerting should land in Azure Monitor/Log Analytics with action groups hitting PagerDuty/Teams.

## Teardown
Set kube contexts and run:
```bash
./scripts/cleanup.sh
```
The script removes namespaces from both clusters (ignoring missing ones) and executes `terraform destroy` to delete AKS, VNets, and PostgreSQL servers.

## Notes & Tips
- Use Azure Key Vault CSI driver or External Secrets Operator to materialize database credentials in each cluster. The provided secret templates show the keys expected by Deployments and StatefulSets.
- For cross-region traffic, Azure Front Door Standard/Premium handles TLS + WAF while Traffic Manager offers quick DNS-level failover. Pick one based on latency vs. feature needs.
- Backup strategy: Azure PostgreSQL Flexible Server already keeps PITR backups; schedule `az postgres flexible-server backup` plus `pg_dump` to blob storage for additional guardrails.
- Cost: AKS uses a single system pool per region sized for peak load. HPA/Cluster Autoscaler can further reduce steady-state cost in the DR region by allowing node count to scale to zero for workloads marked passive.
