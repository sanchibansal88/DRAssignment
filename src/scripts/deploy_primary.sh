#!/usr/bin/env bash
set -euo pipefail

PRIMARY_KUBE_CONTEXT="microservices-primary"
HUB_SERVICE_TOKEN="0ee9b69d57e9560edb7c12db6b1b4cec94430018b6a3bfa05ce05b22b7c15baf"
PROXY_SECRET_TOKEN="19558982cf46988d3bd135d57804ff7fa4852454ae466bfbffed515afdc1d009"
: "${PRIMARY_KUBE_CONTEXT?Set PRIMARY_KUBE_CONTEXT to the kubeconfig context for the primary AKS cluster}"
: "${HUB_SERVICE_TOKEN?Generate HUB_SERVICE_TOKEN for jupyterhub internal services}"
: "${PROXY_SECRET_TOKEN?Generate PROXY_SECRET_TOKEN for the JupyterHub proxy}"

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
FRONTEND_NAMESPACE=${FRONTEND_NAMESPACE:-app-platform}
FRONTEND_HELM_RELEASE=${FRONTEND_HELM_RELEASE:-frontend-api}
FRONTEND_IMAGE_REPOSITORY=${FRONTEND_IMAGE_REPOSITORY:-acrmicroservicesluwh.azurecr.io/app}
FRONTEND_IMAGE_TAG=${FRONTEND_IMAGE_TAG:-v1}
FRONTEND_REPLICA_COUNT=${FRONTEND_REPLICA_COUNT:-3}
FRONTEND_JUPYTERHUB_BASE_URL=${FRONTEND_JUPYTERHUB_BASE_URL:-https://notebooks.example.com}
STORAGE_SECRET_NAME=${STORAGE_SECRET_NAME:-storage-credentials}
STORAGE_SUBSCRIPTION=${STORAGE_SUBSCRIPTION:-microservices}
STORAGE_RESOURCE_GROUP=${STORAGE_RESOURCE_GROUP:-sourcerg}
STORAGE_ACCOUNT_NAME=${STORAGE_ACCOUNT_NAME:-sourcestoragems}
STORAGE_CONTAINER_NAME=${STORAGE_CONTAINER_NAME:-user-data}
STORAGE_BLOB_NAME=${STORAGE_BLOB_NAME:-sample_users.csv}

PRIMARY_TERRAFORM_DIR=${PRIMARY_TERRAFORM_DIR:-$ROOT_DIR/terraform/primary-resrouces}

terraform -chdir="$PRIMARY_TERRAFORM_DIR" init -upgrade
# terraform -chdir="$PRIMARY_TERRAFORM_DIR" apply -auto-approve

az account set --subscription 5656d885-0ab4-4982-8dd7-108f8dc6af81
az aks get-credentials --resource-group rg-microservices-primary --name microservices-primary --overwrite-existing

kubectl --context microservices-primary --namespace app-platform create secret generic database-credentials \
  --from-literal=DATABASE_HOST=microservices-pg.postgres.database.azure.com \
  --from-literal=DATABASE_USER=pgadmin \
  --from-literal=DATABASE_PASSWORD=random123 \
  --from-literal=DATABASE_READ_REPLICA_HOST=microservices-pg-dr.postgres.database.azure.com \
  --from-literal=DATABASE_URL=postgresql://pgadmin:random123@microservices-pg.postgres.database.azure.com:5432/postgres 
  
kubectl --context "$PRIMARY_KUBE_CONTEXT" get namespace "$FRONTEND_NAMESPACE" >/dev/null 2>&1 || \
  kubectl --context "$PRIMARY_KUBE_CONTEXT" create namespace "$FRONTEND_NAMESPACE"

STORAGE_ACCOUNT_KEY=$(az storage account keys list \
  --subscription "$STORAGE_SUBSCRIPTION" \
  --resource-group "$STORAGE_RESOURCE_GROUP" \
  --account-name "$STORAGE_ACCOUNT_NAME"  \
  --query '[0].value' -o tsv)

kubectl --context "$PRIMARY_KUBE_CONTEXT" \
  --namespace "$FRONTEND_NAMESPACE" \
  create secret generic "$STORAGE_SECRET_NAME" \
  --from-literal=STORAGE_ACCOUNT_NAME="$STORAGE_ACCOUNT_NAME" \
  --from-literal=STORAGE_ACCOUNT_KEY="$STORAGE_ACCOUNT_KEY" \
  --from-literal=STORAGE_CONTAINER="$STORAGE_CONTAINER_NAME" \
  --from-literal=STORAGE_BLOB="$STORAGE_BLOB_NAME" \
  --dry-run=client -o yaml | kubectl --context "$PRIMARY_KUBE_CONTEXT" --namespace "$FRONTEND_NAMESPACE" apply -f -

helm upgrade --install "$FRONTEND_HELM_RELEASE" "$ROOT_DIR/helm/frontend-api" \
  --namespace "$FRONTEND_NAMESPACE" \
  --create-namespace \
  --kube-context "$PRIMARY_KUBE_CONTEXT" \
  --set image.repository="$FRONTEND_IMAGE_REPOSITORY" \
  --set image.tag="$FRONTEND_IMAGE_TAG" \
  --set replicaCount="$FRONTEND_REPLICA_COUNT" \
  --set config.serviceMode=active \
  --set config.jupyterHubBaseUrl="$FRONTEND_JUPYTERHUB_BASE_URL"

helm repo add jupyterhub https://jupyterhub.github.io/helm-chart >/dev/null
helm repo update >/dev/null
PRIMARY_VALUES=$(mktemp)
trap 'rm -f "$PRIMARY_VALUES"' EXIT
envsubst < "$ROOT_DIR/k8s/jupyterhub/values-primary.yaml" > "$PRIMARY_VALUES"
helm upgrade --install jupyterhub jupyterhub/jupyterhub \
  --namespace notebooks \
  --create-namespace \
  --kube-context "$PRIMARY_KUBE_CONTEXT" \
  --version 4.3.1 \
  --values "$PRIMARY_VALUES"

echo "Primary region deployed."
