#!/usr/bin/env bash
set -euo pipefail

# Builds the services image and pushes it to the specified Azure Container Registry.
# Usage:
#   ./build_and_push.sh <registry-name> [image-name] [image-tag]
# Example:
#   ./build_and_push.sh myacr app v1.2.3

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_DIR="${SCRIPT_DIR}"

usage() {
  cat <<USAGE
Usage: $(basename "$0") <registry-name> [image-name] [image-tag]

Arguments:
  registry-name  Required. Azure Container Registry name (without .azurecr.io).
  image-name     Optional. Defaults to "app".
  image-tag      Optional. Defaults to "latest".
USAGE
}

if ! command -v az >/dev/null 2>&1; then
  echo "Azure CLI (az) is required but not found in PATH." >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker CLI is required but not found in PATH." >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required but not found in PATH." >&2
  exit 1
fi

REGISTRY="${1:-}"
IMAGE_NAME="${2:-app}"
IMAGE_TAG="${3:-latest}"

if [[ -z "${REGISTRY}" ]]; then
  usage >&2
  exit 1
fi

echo "Ensuring admin user is enabled on ACR: ${REGISTRY}..."
az acr update -n "${REGISTRY}" --admin-enabled true
LOGIN_SERVER="$(az acr show --name "${REGISTRY}" --query loginServer -o tsv)"

ACR_CREDENTIALS=$(az acr credential show --name "${REGISTRY}" --resource-group "rg-microservices-primary" --query "{username:username,password:passwords[0].value}" -o json)
ACR_USERNAME=$(echo "${ACR_CREDENTIALS}" | jq -r '.username')
ACR_PASSWORD=$(echo "${ACR_CREDENTIALS}" | jq -r '.password')

if [[ -z "${ACR_USERNAME}" || -z "${ACR_PASSWORD}" ]]; then
  echo "Failed to fetch ACR credentials." >&2
  exit 1
fi

FULL_IMAGE="${LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "Logging into Docker with ACR credentials..."
echo "${ACR_PASSWORD}" | docker login "${LOGIN_SERVER}" --username "${ACR_USERNAME}" --password-stdin

echo "Building ${FULL_IMAGE} from ${SERVICE_DIR}..."
cd ${SERVICE_DIR}
docker buildx build --platform linux/amd64 . -t "${FULL_IMAGE}"
cd -
# docker buildx build --platform linux/arm64 . -t acrmicroservicesluwh.azurecr.io/app:latest 

echo "Pushing ${FULL_IMAGE}..."
docker push "${FULL_IMAGE}"

echo "Image pushed: ${FULL_IMAGE}"
