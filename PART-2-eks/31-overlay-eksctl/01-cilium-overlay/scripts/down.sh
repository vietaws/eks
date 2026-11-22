#!/usr/bin/env bash
# Delete the whole Cilium overlay demo. The ALB goes first, otherwise its ENIs and
# security groups block the VPC deletion. All names come from ../config.env.
# Usage: ./scripts/down.sh [aws-profile]  (no argument = default AWS profile)
set -euo pipefail

# shellcheck source=SCRIPTDIR/../../lib/common.sh
. "$(dirname "$0")/../../lib/common.sh"
load_config
require_tools eksctl kubectl helm aws python3
use_profile "${1:-}"
render

if cluster_exists; then
  aws eks update-kubeconfig --name "$CLUSTER_NAME" >/dev/null
  echo "==> 1/2 Delete the Ingress, wait for the ALB $ALB_NAME to disappear, uninstall the controller"
  delete_alb_and_controller
else
  echo "Cluster $CLUSTER_NAME not found, skipping Kubernetes cleanup."
fi

echo "==> 2/2 Delete the cluster (node group, add-ons, Pod Identity role, VPC, subnets, IAM)"
eksctl delete cluster --name "$CLUSTER_NAME" --region "$REGION" --disable-nodegroup-eviction --wait
echo "Done."
