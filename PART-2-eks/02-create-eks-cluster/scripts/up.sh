#!/usr/bin/env bash
# Create the shared demo cluster (about 15-20 minutes).
#
#   --mode=standard (default)  cluster.yaml       OIDC + Pod Identity agent + one PUBLIC managed node group
#   --mode=auto                cluster-auto.yaml  EKS Auto Mode, no node group (Auto Mode launches its own nodes)
#
# Usage: ./scripts/up.sh [--mode=standard|auto] [--cluster-name=NAME] [--region=REGION] [--version=1.NN]
#                        [--node-type=TYPE] [--node-count=N] [--node-max=N] [--profile=AWS_PROFILE]
# Every option also accepts the "--option VALUE" form and falls back to an environment variable
# (MODE, CLUSTER_NAME, AWS_REGION, K8S_VERSION, NODE_TYPE, NODE_COUNT, NODE_MAX), then to the default.
# No profile = the AWS default credential chain (AWS_PROFILE if set, otherwise [default]).
set -euo pipefail

SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$SELF")/.."

usage() { sed -n '2,/^set -euo/p' "$SELF" | sed '$d' | sed 's/^# \{0,1\}//'; }

MODE="${MODE:-standard}"
CLUSTER_NAME="${CLUSTER_NAME:-eksdemo}"
K8S_VERSION="${K8S_VERSION:-1.37}"
AWS_REGION="${AWS_REGION:-ap-southeast-1}"
NODE_TYPE="${NODE_TYPE:-t9g.medium}"   # mode=standard only: instance type of the managed node group
NODE_COUNT="${NODE_COUNT:-2}"         # mode=standard only: node group size
NODE_MAX="${NODE_MAX:-}"              # mode=standard only: defaults to NODE_COUNT + 2

while [ $# -gt 0 ]; do
  opt="$1"; val=""
  case "$opt" in
    -h|--help) usage; exit 0 ;;
    --*=*) val="${opt#*=}"; opt="${opt%%=*}" ; shift ;;
    --*) [ $# -ge 2 ] || { echo "option $opt needs a value" >&2; exit 1; }; val="$2"; shift 2 ;;
    *) echo "unexpected argument '$opt' (use --help)" >&2; exit 1 ;;
  esac
  case "$opt" in
    --mode) MODE="$val" ;;
    --cluster-name) CLUSTER_NAME="$val" ;;
    --region) AWS_REGION="$val" ;;
    --version) K8S_VERSION="$val" ;;
    --node-type) NODE_TYPE="$val" ;;
    --node-count) NODE_COUNT="$val" ;;
    --node-max) NODE_MAX="$val" ;;
    --profile) export AWS_PROFILE="$val" ;;
    *) echo "unknown option '$opt' (use --help)" >&2; exit 1 ;;
  esac
done

MODE="$(printf '%s' "$MODE" | tr '[:upper:]' '[:lower:]')"
[[ "$NODE_COUNT" =~ ^[0-9]+$ ]] && : "${NODE_MAX:=$((NODE_COUNT + 2))}"

# Values are substituted into YAML with sed, so keep them to a safe character set.
[[ "$CLUSTER_NAME" =~ ^[A-Za-z][-A-Za-z0-9]{0,99}$ ]] || { echo "CLUSTER_NAME '$CLUSTER_NAME' is not valid (letters, digits, '-', start with a letter)" >&2; exit 1; }
[[ "$K8S_VERSION" =~ ^1\.[0-9]{2}$ ]] || { echo "K8S_VERSION '$K8S_VERSION' must look like 1.37" >&2; exit 1; }
[[ "$AWS_REGION" =~ ^[a-z]{2}(-[a-z]+)+-[0-9]$ ]] || { echo "AWS_REGION '$AWS_REGION' is not valid" >&2; exit 1; }
[[ "$NODE_TYPE" =~ ^[a-z0-9]+\.[a-z0-9]+$ ]] || { echo "NODE_TYPE '$NODE_TYPE' is not valid (for example t9g.small)" >&2; exit 1; }
[[ "$NODE_COUNT" =~ ^[0-9]+$ && "$NODE_MAX" =~ ^[0-9]+$ ]] || { echo "--node-count and --node-max must be numbers" >&2; exit 1; }
case "$MODE" in
  standard) CONFIG=cluster.yaml ;;
  auto) CONFIG=cluster-auto.yaml ;;
  *) echo "--mode must be 'standard' or 'auto' (got '$MODE')" >&2; exit 1 ;;
esac

for tool in eksctl kubectl aws; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 1; }
done

# 22-karpenter needs eksctl >= 0.230.0 (Karpenter getting-started guide). Warn only, Auto Mode works with older releases.
EKSCTL_HAVE="$(eksctl version | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+).*/\1/')"
EKSCTL_NEED=0.230.0
if [ "$(printf '%s\n%s\n' "$EKSCTL_NEED" "$EKSCTL_HAVE" | sort -V | head -n1)" != "$EKSCTL_NEED" ]; then
  echo "WARNING: eksctl $EKSCTL_HAVE is older than $EKSCTL_NEED (needed by the Karpenter demo). Upgrade with: brew upgrade eksctl" >&2
fi

ACCOUNT="$(aws sts get-caller-identity --query Account --output text)" ||
  { echo "AWS credentials not usable for profile '${AWS_PROFILE:-default}'" >&2; exit 1; }
echo "AWS profile: ${AWS_PROFILE:-default}  account: $ACCOUNT  region: $AWS_REGION"
echo "Cluster: $CLUSTER_NAME  version: $K8S_VERSION  mode: $MODE  config: $CONFIG$([ "$MODE" = standard ] && echo "  nodes: ${NODE_COUNT} x ${NODE_TYPE}")"

if eksctl get cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "Cluster $CLUSTER_NAME already exists in $AWS_REGION. Delete it first with ./scripts/down.sh or pick another --cluster-name." >&2
  exit 1
fi

echo "==> 1/3 Create the cluster (control plane + VPC$([ "$MODE" = standard ] && echo " + public node group"))"
sed -e "s|\${CLUSTER_NAME}|${CLUSTER_NAME}|g" \
    -e "s|\${AWS_REGION}|${AWS_REGION}|g" \
    -e "s|\${K8S_VERSION}|${K8S_VERSION}|g" \
    -e "s|\${NODE_TYPE}|${NODE_TYPE}|g" \
    -e "s|\${NODE_COUNT}|${NODE_COUNT}|g" \
    -e "s|\${NODE_MAX}|${NODE_MAX}|g" "$CONFIG" |
  eksctl create cluster -f -

echo "==> 2/3 Write kubeconfig"
eksctl utils write-kubeconfig --cluster "$CLUSTER_NAME" --region "$AWS_REGION"

echo "==> 3/3 Verify"
kubectl get nodes -o wide || true
echo "OIDC issuer: $(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --query 'cluster.identity.oidc.issuer' --output text)"
if [ "$MODE" = auto ]; then
  echo "Auto Mode has no nodes until a pod needs one. Check: kubectl get nodepools"
fi
echo
echo "Done. Delete everything when finished: ./scripts/down.sh   (enter $CLUSTER_NAME and $AWS_REGION when prompted)"
