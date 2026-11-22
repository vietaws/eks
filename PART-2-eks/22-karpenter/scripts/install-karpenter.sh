#!/usr/bin/env bash
# Install Karpenter on the shared MODE=standard cluster from 02-create-eks-cluster (about 5 minutes).
# Mirrors https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/ for the managed node group path:
#   CloudFormation (node role, controller policies, SQS interruption queue) -> Spot service-linked role
#   -> Pod Identity association -> node role access -> Helm chart.
#
# Usage: [CLUSTER_NAME=..] [AWS_REGION=..] [KARPENTER_VERSION=..] ./scripts/install-karpenter.sh [aws-profile]
set -euo pipefail

if [ -n "${1:-}" ]; then
  export AWS_PROFILE="$1"
fi

CLUSTER_NAME="${CLUSTER_NAME:-eksdemo}"
AWS_REGION="${AWS_REGION:-ap-southeast-1}"
KARPENTER_VERSION="${KARPENTER_VERSION:-1.15.3}" # compatibility: Karpenter 1.15.x supports Kubernetes up to 1.37
KARPENTER_NAMESPACE="${KARPENTER_NAMESPACE:-kube-system}"
AWS_PARTITION="${AWS_PARTITION:-aws}"

[[ "$CLUSTER_NAME" =~ ^[A-Za-z][-A-Za-z0-9]{0,99}$ ]] || { echo "CLUSTER_NAME '$CLUSTER_NAME' is not valid" >&2; exit 1; }
[[ "$KARPENTER_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "KARPENTER_VERSION '$KARPENTER_VERSION' must look like 1.15.3" >&2; exit 1; }

for tool in aws eksctl kubectl helm curl; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 1; }
done

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)" ||
  { echo "AWS credentials not usable for profile '${AWS_PROFILE:-default}'" >&2; exit 1; }
echo "AWS profile: ${AWS_PROFILE:-default}  account: $AWS_ACCOUNT_ID  region: $AWS_REGION"

K8S_VERSION="$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --query cluster.version --output text)" ||
  { echo "Cluster $CLUSTER_NAME not found. Run: ../02-create-eks-cluster/scripts/up.sh --mode=standard --cluster-name=$CLUSTER_NAME --region=$AWS_REGION" >&2; exit 1; }
echo "Cluster: $CLUSTER_NAME  Kubernetes: $K8S_VERSION  Karpenter: $KARPENTER_VERSION"
eksctl utils write-kubeconfig --cluster "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null

echo "==> 1/5 CloudFormation: KarpenterNodeRole, controller policies, interruption queue + EventBridge rules"
TEMPOUT="$(mktemp)"
trap 'rm -f "$TEMPOUT"' EXIT
curl -fsSL "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${KARPENTER_VERSION}/website/content/en/preview/getting-started/getting-started-with-karpenter/cloudformation.yaml" >"$TEMPOUT"
aws cloudformation deploy \
  --region "$AWS_REGION" \
  --stack-name "Karpenter-${CLUSTER_NAME}" \
  --template-file "$TEMPOUT" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "ClusterName=${CLUSTER_NAME}"

echo "==> 2/5 Spot service-linked role (one time per account, an error means it already exists)"
aws iam create-service-linked-role --aws-service-name spot.amazonaws.com 2>/dev/null || true

echo "==> 3/5 Pod Identity association for the karpenter service account"
POLICY_PREFIX="arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:policy/KarpenterController"
POLICIES=""
for p in NodeLifecycle IAMIntegration EKSIntegration Interruption ResourceDiscovery ZonalShift; do
  POLICIES="${POLICIES:+$POLICIES,}${POLICY_PREFIX}${p}Policy-${CLUSTER_NAME}"
done
if eksctl get podidentityassociation --cluster "$CLUSTER_NAME" --region "$AWS_REGION" \
    --namespace "$KARPENTER_NAMESPACE" --service-account-name karpenter >/dev/null 2>&1; then
  echo "    already exists, skipping"
else
  eksctl create podidentityassociation --cluster "$CLUSTER_NAME" --region "$AWS_REGION" \
    --namespace "$KARPENTER_NAMESPACE" --service-account-name karpenter \
    --role-name "${CLUSTER_NAME}-karpenter" \
    --permission-policy-arns "$POLICIES"
fi

echo "==> 4/5 Allow nodes launched with KarpenterNodeRole to join the cluster"
NODE_ROLE_ARN="arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:role/KarpenterNodeRole-${CLUSTER_NAME}"
if eksctl get iamidentitymapping --cluster "$CLUSTER_NAME" --region "$AWS_REGION" --arn "$NODE_ROLE_ARN" >/dev/null 2>&1; then
  echo "    already mapped, skipping"
else
  eksctl create iamidentitymapping --cluster "$CLUSTER_NAME" --region "$AWS_REGION" \
    --arn "$NODE_ROLE_ARN" \
    --username 'system:node:{{EC2PrivateDNSName}}' \
    --group system:bootstrappers --group system:nodes
fi

echo "==> 5/5 Helm install Karpenter ${KARPENTER_VERSION}"
helm registry logout public.ecr.aws >/dev/null 2>&1 || true
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version "$KARPENTER_VERSION" \
  --namespace "$KARPENTER_NAMESPACE" --create-namespace \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.interruptionQueue=${CLUSTER_NAME}" \
  --set controller.resources.requests.cpu=1 \
  --set controller.resources.requests.memory=1Gi \
  --set controller.resources.limits.cpu=1 \
  --set controller.resources.limits.memory=1Gi \
  --wait

kubectl get pods -n "$KARPENTER_NAMESPACE" -l app.kubernetes.io/name=karpenter
echo
echo "Karpenter is installed. Next: 02-implement (EC2NodeClass + NodePool)."
