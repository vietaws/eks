#!/usr/bin/env bash
# Build the whole Cilium overlay demo with eksctl. Takes about 20-25 minutes.
# All names, CIDRs and versions come from ../config.env.
# Safe to re-run: steps that are already done are skipped.
# Usage: ./scripts/up.sh [aws-profile]      (no argument = default AWS profile)
set -euo pipefail

# shellcheck source=SCRIPTDIR/../../lib/common.sh
. "$(dirname "$0")/../../lib/common.sh"
load_config
require_tools eksctl kubectl helm aws python3
use_profile "${1:-}"

check_cidrs "disjoint:$VPC_CIDR:$POD_CIDR" "disjoint:$VPC_CIDR:$SERVICE_CIDR" "disjoint:$POD_CIDR:$SERVICE_CIDR"
render

echo "==> 1/7 Cluster: $VPC_CIDR VPC split by eksctl (no NAT), control plane, kube-proxy + pod-identity add-ons"
if cluster_exists; then
  echo "    cluster $CLUSTER_NAME already exists, skipping"
  aws eks update-kubeconfig --name "$CLUSTER_NAME" >/dev/null
else
  eksctl create cluster -f "$RENDER_DIR/cluster.yaml"
fi

echo "==> 2/7 Pod Identity association for the AWS Load Balancer Controller"
if [ "$(aws eks list-pod-identity-associations --cluster-name "$CLUSTER_NAME" --namespace kube-system \
  --service-account "$LBC_SERVICE_ACCOUNT" --query 'length(associations)' --output text)" != "0" ]; then
  echo "    association for kube-system/$LBC_SERVICE_ACCOUNT already exists, skipping"
else
  eksctl create podidentityassociation -f "$RENDER_DIR/pod-identity.yaml"
fi

echo "==> 3/7 Cilium $CILIUM_VERSION overlay, pod CIDR $POD_CIDR (nodes cannot become Ready without a CNI)"
helm repo add cilium https://helm.cilium.io/ >/dev/null 2>&1 || true
helm repo update cilium >/dev/null
helm upgrade --install cilium cilium/cilium --version "$CILIUM_VERSION" \
  --namespace kube-system -f "$RENDER_DIR/manifests/cilium-values.yaml"

echo "==> 4/7 Managed node group $NODEGROUP_NAME (tainted until Cilium is ready, maxPods=$MAX_PODS)"
if nodegroup_exists "$NODEGROUP_NAME"; then
  echo "    node group $NODEGROUP_NAME already exists, skipping"
else
  eksctl create nodegroup -f "$RENDER_DIR/nodegroup.yaml"
fi

echo "==> 5/7 CoreDNS add-on (needs Ready nodes)"
if aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name coredns >/dev/null 2>&1; then
  echo "    coredns add-on already exists, skipping"
else
  eksctl create addon --cluster "$CLUSTER_NAME" --name coredns
fi

echo "==> 6/7 AWS Load Balancer Controller $LBC_CHART_VERSION (hostNetwork: the control plane cannot reach overlay pod IPs)"
VPC_ID=$(vpc_id)
helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1 || true
helm repo update eks >/dev/null
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --version "$LBC_CHART_VERSION" -n kube-system \
  -f "$RENDER_DIR/manifests/lbc-values.yaml" --set vpcId="$VPC_ID" --wait --timeout 5m

echo "==> 7/7 App and ALB"
kubectl apply -f "$RENDER_DIR/manifests/01-app.yaml" -f "$RENDER_DIR/manifests/02-ingress-class.yaml" \
  -f "$RENDER_DIR/manifests/03-alb.yaml"

echo
echo "Done. VPC: $VPC_ID"
echo "Next: watch 'kubectl get ingress $INGRESS_NAME -w', then follow the Validation section of the README."
