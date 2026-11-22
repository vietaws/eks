#!/usr/bin/env bash
# Build the secondary-CIDR demo at STAGE 0 (stock VPC CNI, pods in the main subnets). Takes about 20 minutes.
# Move to stage 1 and 2 with scripts/stage.sh. All names, CIDRs and versions come from ../config.env.
# Safe to re-run: steps that are already done are skipped.
# Usage: ./scripts/up.sh [aws-profile]  (no argument = default AWS profile)
set -euo pipefail

# shellcheck source=SCRIPTDIR/../../lib/common.sh
. "$(dirname "$0")/../../lib/common.sh"
load_config
require_tools eksctl kubectl helm aws python3
use_profile "${1:-}"

check_cidrs "inside:$POD_SUBNET_1_CIDR:$SECONDARY_CIDR" "inside:$POD_SUBNET_2_CIDR:$SECONDARY_CIDR" \
  "disjoint:$POD_SUBNET_1_CIDR:$POD_SUBNET_2_CIDR" "disjoint:$VPC_CIDR:$SECONDARY_CIDR" \
  "disjoint:$VPC_CIDR:$SERVICE_CIDR" "disjoint:$SECONDARY_CIDR:$SERVICE_CIDR"
render

echo "==> 1/7 Pre-flight: $VPC_CIDR and $SECONDARY_CIDR must not overlap any VPC in this account/region (peering rule)"
if cluster_exists; then
  echo "    cluster $CLUSTER_NAME already exists (its own VPC would match), skipping"
else
  "$DEMO_DIR/scripts/preflight-cidr.sh"
fi

echo "==> 2/7 Cluster: $VPC_CIDR VPC split by eksctl (no NAT), control plane, add-ons, LBC role"
if cluster_exists; then
  echo "    cluster $CLUSTER_NAME already exists, skipping"
  aws eks update-kubeconfig --name "$CLUSTER_NAME" >/dev/null
else
  eksctl create cluster -f "$RENDER_DIR/cluster.yaml"
fi

echo "==> 3/7 Secondary CIDR $SECONDARY_CIDR + pod subnets $POD_SUBNET_1_CIDR, $POD_SUBNET_2_CIDR"
"$DEMO_DIR/scripts/secondary-cidr.sh" create

echo "==> 4/7 Stage-0 node group ${NODEGROUP_PREFIX}0 (stock VPC CNI, default maxPods)"
if nodegroup_exists "${NODEGROUP_PREFIX}0"; then
  echo "    node group ${NODEGROUP_PREFIX}0 already exists, skipping"
else
  eksctl create nodegroup -f "$RENDER_DIR/nodegroup-s0.yaml"
fi

echo "==> 5/7 ENIConfig per AZ (created now so stage-1 nodes find them at boot)"
"$DEMO_DIR/scripts/eniconfig.sh"

echo "==> 6/7 AWS Load Balancer Controller $LBC_CHART_VERSION (normal install: pods are VPC-routable, webhooks work)"
VPC_ID=$(vpc_id)
helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1 || true
helm repo update eks >/dev/null
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --version "$LBC_CHART_VERSION" -n kube-system \
  -f "$RENDER_DIR/manifests/lbc-values.yaml" --set vpcId="$VPC_ID" --wait --timeout 5m

echo "==> 7/7 App and ALB (target-type ip)"
kubectl apply -f "$RENDER_DIR/manifests/01-app.yaml" -f "$RENDER_DIR/manifests/02-ingress-class.yaml" \
  -f "$RENDER_DIR/manifests/03-alb.yaml"

echo
echo "Done (stage 0). VPC: $VPC_ID"
echo "Next: follow the README: baseline reading, scale to 40 pods, then ./scripts/stage.sh 1 and 2."
