#!/usr/bin/env bash
# Tear down the course cluster completely.
# Usage: ./cluster-down.sh
set -euo pipefail
CLUSTER_NAME="k8s-course"
echo "Deleting kind cluster '${CLUSTER_NAME}'..."
kind delete cluster --name "${CLUSTER_NAME}"
echo "Done."
