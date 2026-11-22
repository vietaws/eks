#!/usr/bin/env bash
# Delete the shared demo cluster and everything the demos created on top of it.
# Order matters: load balancers and volumes first (they hold ENIs and block the VPC delete), then
# Karpenter / Auto Mode nodes, then the Karpenter CloudFormation stack, then the cluster itself.
#
# Usage: ./scripts/down.sh [--cluster-name=NAME] [--region=REGION] [--profile=AWS_PROFILE] [--force]
# Without --cluster-name / --region the script prompts for them. Press Enter to accept the default
# shown in brackets (CLUSTER_NAME / AWS_REGION env vars if set, otherwise eksdemo / ap-southeast-1),
# or type another value. --force (or FORCE=1) skips the final yes/no confirmation.
set -euo pipefail

SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
CLUSTER_NAME_ARG=""; AWS_REGION_ARG=""; FORCE="${FORCE:-0}"
while [ $# -gt 0 ]; do
  opt="$1"; val=""
  case "$opt" in
    -h|--help) sed -n '2,/^set -euo/p' "$SELF" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    --force) FORCE=1; shift; continue ;;
    --*=*) val="${opt#*=}"; opt="${opt%%=*}"; shift ;;
    --*) [ $# -ge 2 ] || { echo "option $opt needs a value" >&2; exit 1; }; val="$2"; shift 2 ;;
    *) echo "unexpected argument '$opt' (use --help)" >&2; exit 1 ;;
  esac
  case "$opt" in
    --cluster-name) CLUSTER_NAME_ARG="$val" ;;
    --region) AWS_REGION_ARG="$val" ;;
    --profile) export AWS_PROFILE="$val" ;;
    *) echo "unknown option '$opt' (use --help)" >&2; exit 1 ;;
  esac
done

ask() {  # ask VAR "label" default [preset]: preset (from a flag) skips the prompt
  local var="$1" label="$2" def="$3" preset="${4:-}" reply=""
  if [ -n "$preset" ]; then printf -v "$var" '%s' "$preset"; return; fi
  [ -t 0 ] || { echo "No terminal to prompt for $label. Pass it as an option (see --help)." >&2; exit 1; }
  read -r -p "$label [$def]: " reply
  printf -v "$var" '%s' "${reply:-$def}"
}
ask CLUSTER_NAME "Cluster name" "${CLUSTER_NAME:-eksdemo}" "$CLUSTER_NAME_ARG"
ask AWS_REGION "AWS region" "${AWS_REGION:-ap-southeast-1}" "$AWS_REGION_ARG"
[[ "$CLUSTER_NAME" =~ ^[A-Za-z][-A-Za-z0-9]{0,99}$ ]] || { echo "Cluster name '$CLUSTER_NAME' is not valid" >&2; exit 1; }
[[ "$AWS_REGION" =~ ^[a-z]{2}(-[a-z]+)+-[0-9]$ ]] || { echo "AWS region '$AWS_REGION' is not valid" >&2; exit 1; }

for tool in eksctl kubectl aws jq; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 1; }
done

ACCOUNT="$(aws sts get-caller-identity --query Account --output text)" ||
  { echo "AWS credentials not usable for profile '${AWS_PROFILE:-default}'" >&2; exit 1; }
echo "AWS profile: ${AWS_PROFILE:-default}  account: $ACCOUNT  region: $AWS_REGION"
echo "About to DELETE cluster '$CLUSTER_NAME' and all workloads, load balancers, volumes and nodes in it."
if [ "$FORCE" != 1 ]; then
  [ -t 0 ] || { echo "No terminal to confirm. Pass --force to delete without confirmation." >&2; exit 1; }
  read -r -p "Delete cluster '$CLUSTER_NAME' in $AWS_REGION (account $ACCOUNT)? Type 'yes' to continue: " CONFIRM
  [ "$CONFIRM" = yes ] || { echo "Aborted." >&2; exit 1; }
fi

if eksctl get cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  eksctl utils write-kubeconfig --cluster "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null

  echo "==> 1/5 Delete Ingresses and LoadBalancer Services (the controller removes the AWS load balancers)"
  kubectl delete ingress --all --all-namespaces --wait=true --timeout=300s || true
  kubectl get svc --all-namespaces -o json |
    jq -r '.items[] | select(.spec.type=="LoadBalancer") | "\(.metadata.namespace) \(.metadata.name)"' |
    while read -r ns name; do
      kubectl delete svc -n "$ns" "$name" --wait=true --timeout=300s || true
    done

  echo "==> 2/5 Delete workloads and PersistentVolumeClaims outside kube-* namespaces (releases EBS volumes)"
  for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
    case "$ns" in kube-*) continue ;; esac
    kubectl delete deployment,statefulset,daemonset,job,cronjob --all -n "$ns" --wait=true --timeout=300s || true
    kubectl delete pvc --all -n "$ns" --wait=true --timeout=300s || true
  done

  echo "==> 3/5 Delete Karpenter / Auto Mode custom NodePools and wait until their nodes are gone"
  # Built-in Auto Mode pools (system, general-purpose) are owned by AWS; everything else is ours.
  for np in $(kubectl get nodepool -o name 2>/dev/null | grep -vE '/(system|general-purpose)$' || true); do
    kubectl delete "$np" --wait=false || true
  done
  kubectl delete ec2nodeclass --all --wait=false 2>/dev/null || true
  kubectl wait --for=delete nodeclaim --all --timeout=600s 2>/dev/null || true
  if command -v helm >/dev/null && helm status karpenter -n kube-system >/dev/null 2>&1; then
    helm uninstall karpenter -n kube-system || true
  fi

  echo "==> 4/5 Remove Karpenter AWS resources (launch templates, CloudFormation stack) if present"
  for lt in $(aws ec2 describe-launch-templates --region "$AWS_REGION" \
      --filters "Name=tag:karpenter.k8s.aws/cluster,Values=${CLUSTER_NAME}" \
      --query 'LaunchTemplates[].LaunchTemplateName' --output text); do
    aws ec2 delete-launch-template --region "$AWS_REGION" --launch-template-name "$lt" >/dev/null
  done
  if aws cloudformation describe-stacks --region "$AWS_REGION" --stack-name "Karpenter-${CLUSTER_NAME}" >/dev/null 2>&1; then
    aws cloudformation delete-stack --region "$AWS_REGION" --stack-name "Karpenter-${CLUSTER_NAME}"
    aws cloudformation wait stack-delete-complete --region "$AWS_REGION" --stack-name "Karpenter-${CLUSTER_NAME}"
  fi
else
  echo "Cluster $CLUSTER_NAME not found, skipping Kubernetes cleanup."
fi

echo "==> 5/5 Delete the cluster (node groups, add-ons, Pod Identity roles, VPC, IAM)"
if eksctl get cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  eksctl delete cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --disable-nodegroup-eviction --wait
fi

echo "==> Leftover check (resources still tagged for this cluster)"
LEFT="$(aws resourcegroupstaggingapi get-resources --region "$AWS_REGION" \
  --tag-filters "Key=kubernetes.io/cluster/${CLUSTER_NAME}" \
  --query 'ResourceTagMappingList[].ResourceARN' --output text)"
if [ -n "$LEFT" ]; then
  echo "Still present, delete manually if they are not needed:" >&2
  echo "$LEFT" | tr '\t' '\n' >&2
else
  echo "Nothing left."
fi
echo "Done."
