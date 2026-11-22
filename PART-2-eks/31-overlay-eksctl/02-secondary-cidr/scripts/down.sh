#!/usr/bin/env bash
# Delete the whole secondary-CIDR demo. Order matters: the ALB, the node groups and the pod subnets
# are not owned by the eksctl VPC stack and would block the VPC deletion. Names come from ../config.env.
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

  echo "==> 1/4 Delete the Ingress, wait for the ALB $ALB_NAME to disappear, uninstall the controller"
  delete_alb_and_controller

  # Node groups go before the pod subnets: their nodes hold the pod ENIs in those subnets.
  echo "==> 2/4 Delete all node groups"
  for ng in $(aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --query 'nodegroups[]' --output text); do
    eksctl delete nodegroup --cluster "$CLUSTER_NAME" --name "$ng" --drain=false --wait
  done

  echo "==> 3/4 Delete the pod subnets and disassociate $SECONDARY_CIDR"
  "$DEMO_DIR/scripts/secondary-cidr.sh" delete
else
  echo "Cluster $CLUSTER_NAME not found, skipping Kubernetes, node group and pod subnet cleanup."
fi

echo "==> 4/4 Delete the cluster (add-ons, Pod Identity role, VPC, public/private subnets, IAM)"
eksctl delete cluster --name "$CLUSTER_NAME" --region "$REGION" --disable-nodegroup-eviction --wait
echo "Done."
