#!/usr/bin/env bash
# Simulate an EC2 Spot interruption on one Karpenter Spot node with AWS Fault Injection Service (FIS).
# FIS sends the real 2-minute interruption notice (action aws:ec2:send-spot-instance-interruptions). The notice goes
# through EventBridge and SQS to Karpenter, which taints the node, launches a replacement and drains the old node.
# The script creates a temporary FIS role and experiment template, starts the experiment, and removes both on exit.
# Costs nothing by itself, but the Spot instance really is reclaimed after the notice.
#
# Usage: ./scripts/simulate-spot-interruption.sh [--node=NODE_NAME] [--region=REGION] [--cluster-name=NAME] [--profile=AWS_PROFILE]
# Defaults: first Spot node created by Karpenter; AWS_REGION or ap-southeast-1; CLUSTER_NAME or eksdemo.
# Needs: kubectl, aws, jq. IAM: iam:CreateRole/PutRolePolicy/DeleteRole*, fis:*Experiment*.
set -euo pipefail

NODE=""; REGION="${AWS_REGION:-ap-southeast-1}"; CLUSTER="${CLUSTER_NAME:-eksdemo}"
for arg in "$@"; do
  case "$arg" in
    --node=*) NODE="${arg#*=}" ;;
    --region=*) REGION="${arg#*=}" ;;
    --cluster-name=*) CLUSTER="${arg#*=}" ;;
    --profile=*) export AWS_PROFILE="${arg#*=}" ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option '$arg' (use --help)" >&2; exit 1 ;;
  esac
done
[[ "$REGION" =~ ^[a-z]{2}(-[a-z]+)+-[0-9]$ ]] || { echo "region '$REGION' is not valid" >&2; exit 1; }
[[ "$CLUSTER" =~ ^[A-Za-z][-A-Za-z0-9]{0,99}$ ]] || { echo "cluster name '$CLUSTER' is not valid" >&2; exit 1; }
for tool in kubectl aws jq; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 1; }
done

if [ -z "$NODE" ]; then
  NODE="$(kubectl get nodes -l karpenter.sh/capacity-type=spot -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
fi
[ -n "$NODE" ] || { echo "No Spot node found. Deploy the web app first (see README)." >&2; exit 1; }
CAP="$(kubectl get node "$NODE" -o jsonpath='{.metadata.labels.karpenter\.sh/capacity-type}')"
[ "$CAP" = spot ] || { echo "Node $NODE is '$CAP', not spot." >&2; exit 1; }
INSTANCE_ID="$(kubectl get node "$NODE" -o jsonpath='{.spec.providerID}' | sed 's|.*/||')"
[[ "$INSTANCE_ID" =~ ^i-[0-9a-f]+$ ]] || { echo "could not read the instance id of $NODE" >&2; exit 1; }

ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
ROLE="karpenter-demo-fis-${CLUSTER}"
ARN="arn:aws:ec2:${REGION}:${ACCOUNT}:instance/${INSTANCE_ID}"
TEMPLATE_ID=""
cleanup() {
  [ -n "$TEMPLATE_ID" ] && aws fis delete-experiment-template --region "$REGION" --id "$TEMPLATE_ID" >/dev/null 2>&1 || true
  aws iam delete-role-policy --role-name "$ROLE" --policy-name fis-spot >/dev/null 2>&1 || true
  aws iam delete-role --role-name "$ROLE" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "About to interrupt Spot node $NODE ($INSTANCE_ID) in $REGION, account $ACCOUNT."
if [ -t 0 ]; then
  read -r -p "Type 'yes' to continue: " OK
  [ "$OK" = yes ] || { echo "Aborted." >&2; exit 1; }
fi

echo "==> Create temporary FIS role $ROLE"
aws iam create-role --role-name "$ROLE" --assume-role-policy-document '{
  "Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"fis.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
aws iam put-role-policy --role-name "$ROLE" --policy-name fis-spot --policy-document '{
  "Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["ec2:SendSpotInstanceInterruptions","ec2:DescribeInstances"],"Resource":"*"}]}'
sleep 15 # IAM propagation

echo "==> Create and start the experiment (2-minute notice)"
TEMPLATE_ID="$(aws fis create-experiment-template --region "$REGION" \
  --description "Karpenter demo: interrupt one Spot node" \
  --role-arn "arn:aws:iam::${ACCOUNT}:role/${ROLE}" \
  --stop-conditions source=none \
  --targets "{\"spot\":{\"resourceType\":\"aws:ec2:spot-instance\",\"resourceArns\":[\"${ARN}\"],\"selectionMode\":\"ALL\"}}" \
  --actions '{"interrupt":{"actionId":"aws:ec2:send-spot-instance-interruptions","parameters":{"durationBeforeInterruption":"PT2M"},"targets":{"SpotInstances":"spot"}}}' \
  --query 'experimentTemplate.id' --output text)"
EXPERIMENT_ID="$(aws fis start-experiment --region "$REGION" --experiment-template-id "$TEMPLATE_ID" \
  --query 'experiment.id' --output text)"
echo "Experiment $EXPERIMENT_ID started. Watch in other terminals:"
echo "  kubectl get nodes -L karpenter.sh/capacity-type -w"
echo "  kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter -c controller -f | grep -iE 'interrupt|disrupt|launched'"
echo "  kubectl logs deploy/prober --tail=3"
# Keep the role until the experiment ends (about 2 minutes), otherwise deleting it could stop the action early.
for _ in $(seq 1 30); do
  STATE="$(aws fis get-experiment --region "$REGION" --id "$EXPERIMENT_ID" --query 'experiment.state.status' --output text)"
  echo "experiment state: $STATE"
  case "$STATE" in completed|stopped|failed|cancelled) break ;; esac
  sleep 10
done
echo "The temporary role and template are removed when this script exits."
