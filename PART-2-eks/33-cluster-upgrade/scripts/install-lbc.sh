#!/usr/bin/env bash
# Install the AWS Load Balancer Controller (chart and IAM policy from the same release) on a MODE=standard cluster,
# with EKS Pod Identity. Needed so a Service with loadBalancerClass service.k8s.aws/nlb creates an IP-target NLB,
# the same load balancer type that Auto Mode builds natively. Takes about 2 minutes.
#
# Usage: CLUSTER_NAME=.. [AWS_REGION=..] [LBC_VERSION=..] ./scripts/install-lbc.sh
set -euo pipefail
CLUSTER_NAME="${CLUSTER_NAME:?set CLUSTER_NAME}"
AWS_REGION="${AWS_REGION:-ap-southeast-1}"
LBC_VERSION="${LBC_VERSION:-3.6.3}" # chart version = controller version (checked 2026-11). Check the releases page before changing.
[[ "$CLUSTER_NAME" =~ ^[A-Za-z][-A-Za-z0-9]{0,99}$ ]] || { echo "invalid CLUSTER_NAME" >&2; exit 1; }
[[ "$LBC_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "LBC_VERSION must look like 3.6.3" >&2; exit 1; }
for tool in aws eksctl kubectl helm curl; do command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 1; }; done

ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
POLICY_NAME="AWSLoadBalancerControllerIAMPolicy-${CLUSTER_NAME}"
POLICY_ARN="arn:aws:iam::${ACCOUNT}:policy/${POLICY_NAME}"
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT

echo "==> IAM policy $POLICY_NAME (from release v${LBC_VERSION})"
if ! aws iam get-policy --policy-arn "$POLICY_ARN" >/dev/null 2>&1; then
  curl -fsSL "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v${LBC_VERSION}/docs/install/iam_policy.json" >"$TMP"
  aws iam create-policy --policy-name "$POLICY_NAME" --policy-document "file://$TMP" >/dev/null
fi

echo "==> Pod Identity association"
if ! eksctl get podidentityassociation --cluster "$CLUSTER_NAME" --region "$AWS_REGION" \
    --namespace kube-system --service-account-name aws-load-balancer-controller >/dev/null 2>&1; then
  eksctl create podidentityassociation --cluster "$CLUSTER_NAME" --region "$AWS_REGION" \
    --namespace kube-system --service-account-name aws-load-balancer-controller \
    --role-name "${CLUSTER_NAME}-lbc" --permission-policy-arns "$POLICY_ARN"
fi

echo "==> Helm install"
VPC_ID="$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --query cluster.resourcesVpcConfig.vpcId --output text)"
helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1 || true
helm repo update eks >/dev/null
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --version "$LBC_VERSION" --namespace kube-system \
  --set clusterName="$CLUSTER_NAME" --set region="$AWS_REGION" --set vpcId="$VPC_ID" \
  --set serviceAccount.create=true --set serviceAccount.name=aws-load-balancer-controller \
  --set replicaCount=2 --wait
kubectl -n kube-system rollout status deployment/aws-load-balancer-controller
