#!/usr/bin/env bash
set -euo pipefail

# Builds the custom JupyterHub singleuser image and pushes it to the specified ACR.
# Usage:
#   ./build_and_push.sh <registry-name> [image-name] [image-tag]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<USAGE
Usage: $(basename "$0") <registry-name> [image-name] [image-tag]

Arguments:
  registry-name  Required. Azure Container Registry name (without .azurecr.io).
  image-name     Optional. Defaults to "jupyterhub-singleuser".
  image-tag      Optional. Defaults to "4.3.1".
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
IMAGE_NAME="${2:-jupyterhub-singleuser}"
IMAGE_TAG="${3:-5.4.1}"

if [[ -z "${REGISTRY}" ]]; then
  usage >&2
  exit 1
fi

LOGIN_SERVER="$(az acr show --name "${REGISTRY}" --query loginServer -o tsv)"
ACR_CREDENTIALS=$(az acr credential show --name "${REGISTRY}" --query "{username:username,password:passwords[0].value}" -o json)
ACR_USERNAME=$(echo "${ACR_CREDENTIALS}" | jq -r '.username')
ACR_PASSWORD=$(echo "${ACR_CREDENTIALS}" | jq -r '.password')

if [[ -z "${ACR_USERNAME}" || -z "${ACR_PASSWORD}" ]]; then
  echo "Failed to fetch ACR credentials." >&2
  exit 1
fi

FULL_IMAGE="${LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "Logging into Docker registry ${LOGIN_SERVER}..."
echo "${ACR_PASSWORD}" | docker login "${LOGIN_SERVER}" --username "${ACR_USERNAME}" --password-stdin

echo "Building image ${FULL_IMAGE} from ${SCRIPT_DIR}..."
docker build -t "${FULL_IMAGE}" "${SCRIPT_DIR}"

echo "Pushing ${FULL_IMAGE}..."
docker push "${FULL_IMAGE}"

echo "Image pushed: ${FULL_IMAGE}"
