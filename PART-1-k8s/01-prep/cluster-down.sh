#!/usr/bin/env bash
# Tear down the course cluster completely.
# Usage: ./cluster-down.sh
set -euo pipefail
CLUSTER_NAME="vietvn-k8s"
echo "Deleting kind cluster '${CLUSTER_NAME}'..."
kind delete cluster --name "${CLUSTER_NAME}"
echo "Done."
