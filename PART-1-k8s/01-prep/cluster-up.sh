#!/usr/bin/env bash
# Spin up the course's multi-node kind cluster and verify it is Ready.
# Usage: ./cluster-up.sh
set -euo pipefail

CLUSTER_NAME="vietvn-k8s"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${SCRIPT_DIR}/kind-config.yaml"

# --- preflight checks -------------------------------------------------------
for bin in docker kind kubectl; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "ERROR: '$bin' is not installed or not on PATH." >&2
    exit 1
  fi
done

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Docker daemon is not running. Start Docker and retry." >&2
  exit 1
fi

# --- create (idempotent) ----------------------------------------------------
if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "Cluster '${CLUSTER_NAME}' already exists. Skipping create."
else
  echo "Creating kind cluster '${CLUSTER_NAME}'..."
  kind create cluster --name "${CLUSTER_NAME}" --config "${CONFIG}"
fi

# --- verify -----------------------------------------------------------------
# Ensure kubectl points at this cluster (a prior `kind delete` can leave a
# dangling context, causing "connection refused").
kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null 2>&1 || true

echo "Waiting for all nodes to become Ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s

echo
echo "Cluster is up. Nodes:"
kubectl get nodes -o wide
