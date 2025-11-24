#!/usr/bin/env bash
set -euo pipefail

: "${PRIMARY_KUBE_CONTEXT?Set PRIMARY_KUBE_CONTEXT to the primary kube context}"
: "${DR_KUBE_CONTEXT?Set DR_KUBE_CONTEXT to the DR kube context}"

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

for ctx in "$PRIMARY_KUBE_CONTEXT" "$DR_KUBE_CONTEXT"; do
  helm --kube-context "$ctx" uninstall jupyterhub -n notebooks >/dev/null 2>&1 || true
  kubectl --context "$ctx" delete pvc --all -n notebooks --ignore-not-found || true
  kubectl --context "$ctx" delete pvc --all -n app-platform --ignore-not-found || true
  kubectl --context "$ctx" delete namespace notebooks --ignore-not-found
  kubectl --context "$ctx" delete namespace app-platform --ignore-not-found
  echo "Context $ctx cleaned"
done

terraform -chdir="$ROOT_DIR/terraform" destroy -auto-approve
