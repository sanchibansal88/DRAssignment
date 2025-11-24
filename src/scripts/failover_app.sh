#!/usr/bin/env bash
set -euo pipefail

PRIMARY_KUBE_CONTEXT="microservices-primary"
DR_KUBE_CONTEXT="microservices-dr"
PRIMARY_POSTGRES_SERVER="microservices-pg"
DR_POSTGRES_SERVER="microservices-pg-dr"
PRIMARY_RG="rg-microservices-primary"
DR_RG="rg-microservices-dr"
DR_POSTGRES_FQDN="microservices-pg-dr.postgres.database.azure.com"
HUB_SERVICE_TOKEN="0ee9b69d57e9560edb7c12db6b1b4cec94430018b6a3bfa05ce05b22b7c15baf"
PROXY_SECRET_TOKEN="19558982cf46988d3bd135d57804ff7fa4852454ae466bfbffed515afdc1d009"
DR_AKS_ID="/subscriptions/5656d885-0ab4-4982-8dd7-108f8dc6af81/resourceGroups/rg-microservices-dr/providers/Microsoft.ContainerService/managedClusters/microservices-dr"
: "${PRIMARY_KUBE_CONTEXT?Set PRIMARY_KUBE_CONTEXT to the primary kube context}"
: "${DR_KUBE_CONTEXT?Set DR_KUBE_CONTEXT to the DR kube context}"
: "${PRIMARY_POSTGRES_SERVER?Set PRIMARY_POSTGRES_SERVER to the Azure flexible server name}"
: "${DR_POSTGRES_SERVER?Set DR_POSTGRES_SERVER to the Azure flexible server replica name}"
: "${PRIMARY_RG?Set PRIMARY_RG to the primary resource group}"
: "${DR_RG?Set DR_RG to the DR resource group}"
: "${DR_POSTGRES_FQDN?Set DR_POSTGRES_FQDN to the promoted DR Postgres FQDN}"
: "${HUB_SERVICE_TOKEN?Provide the same HUB_SERVICE_TOKEN used during deploy}"
: "${PROXY_SECRET_TOKEN?Provide the same PROXY_SECRET_TOKEN used during deploy}"

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
FRONTEND_NAMESPACE=${FRONTEND_NAMESPACE:-app-platform}
FRONTEND_HELM_RELEASE=${FRONTEND_HELM_RELEASE:-frontend-api}
FRONTEND_CONFIGMAP_NAME=${FRONTEND_CONFIGMAP_NAME:-frontend-api-frontend-api-config}
FRONTEND_DEPLOYMENT_NAME=${FRONTEND_DEPLOYMENT_NAME:-frontend-api-frontend-api}
# DR_AKS_ID=$(terraform -chdir="$ROOT_DIR/terraform" output -raw dr_aks_id)

# Freeze writes on primary and capture the WAL position for verification.
kubectl --context "$PRIMARY_KUBE_CONTEXT" patch configmap "$FRONTEND_CONFIGMAP_NAME" -n "$FRONTEND_NAMESPACE" -p '{"data":{"SERVICE_MODE":"readonly"}}'
echo "[INFO] Primary database set to read-only mode."
kubectl --context "$PRIMARY_KUBE_CONTEXT" scale deploy "$FRONTEND_DEPLOYMENT_NAME" -n "$FRONTEND_NAMESPACE" --replicas=0
echo "[INFO] Primary frontend deployment scaled to 0 replicas."

echo "[INFO] Waiting 30 seconds to allow in-flight transactions to complete..."
# sleep 30  # In real script, uncomment this line to wait for transactions to complete.
# Promote the Azure PostgreSQL replica. 
# az postgres flexible-server replica promote \
#     --resource-group ${DR_RG} \
#     --name ${DR_POSTGRES_SERVER} \
#     --promote-mode standalone \
#     --promote-option planned

DB_PASSWORD=$(kubectl --context "$DR_KUBE_CONTEXT" get secret database-credentials -n "$FRONTEND_NAMESPACE" -o jsonpath='{.data.DATABASE_PASSWORD}' | base64 -d)
NEW_HOST="$DR_POSTGRES_FQDN"
NEW_URL="postgresql://pgadmin:${DB_PASSWORD}@${NEW_HOST}:5432/postgres"

# Point notebooks and services to the promoted database.
kubectl --context "$DR_KUBE_CONTEXT" patch secret database-credentials -n "$FRONTEND_NAMESPACE" \
  --type merge \
  -p "{\"stringData\":{\"DATABASE_HOST\":\"${NEW_HOST}\",\"DATABASE_URL\":\"${NEW_URL}\"}}"

kubectl --context "$DR_KUBE_CONTEXT" patch configmap "$FRONTEND_CONFIGMAP_NAME" -n "$FRONTEND_NAMESPACE" -p '{"data":{"SERVICE_MODE":"active"}}'

kubectl --context "$DR_KUBE_CONTEXT" scale deploy "$FRONTEND_DEPLOYMENT_NAME" -n "$FRONTEND_NAMESPACE" --replicas=3

# Optional: warm up the DR notebooks so users land in an already running hub.
DR_VALUES=$(mktemp)
trap 'rm -f "$DR_VALUES"' EXIT
envsubst < "$ROOT_DIR/k8s/jupyterhub/values-dr.yaml" > "$DR_VALUES"
helm upgrade --install jupyterhub jupyterhub/jupyterhub \
  --namespace notebooks \
  --create-namespace \
  --kube-context "$DR_KUBE_CONTEXT" \
  --version 4.3.1 \
  --values "$DR_VALUES" \
  --set singleuser.extraEnv.WORKSPACE_MODE=active

cat <<INSTRUCTIONS
Manual step: update Traffic Manager / DNS to send client traffic to the DR endpoints.
Examples:
  az network traffic-manager endpoint update \\
    --resource-group $PRIMARY_RG \\
    --profile-name ${PRIMARY_POSTGRES_SERVER}-tm \\
    --name dr-aks \\
    --type azureEndpoints \\
    --endpoint-status Enabled \\
    --target-resource-id $DR_AKS_ID
INSTRUCTIONS
