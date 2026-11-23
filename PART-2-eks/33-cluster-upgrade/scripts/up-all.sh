#!/usr/bin/env bash
# Create the three demo clusters in parallel at the OLD version and prepare each one (about 25 minutes):
#   upg-mng   managed node group only
#   upg-karp  small managed node group (hosts Karpenter) + Karpenter, pinned AMI
#   upg-auto  EKS Auto Mode
# All nodes use NODE_TYPE (default t9g.medium). Three control planes, NAT gateways and node sets bill together.
#
# Usage: [AWS_PROFILE=..] [NODE_TYPE=..] ./scripts/up-all.sh
set -euo pipefail
cd "$(dirname "$0")/.."
export AWS_REGION="${AWS_REGION:-ap-southeast-1}"
OLD_VERSION="${OLD_VERSION:-1.36}"
NODE_TYPE="${NODE_TYPE:-t9g.medium}"
SHARED="../02-create-eks-cluster/scripts/up.sh"
LOGS="${TMPDIR:-/tmp}/upg-logs"
mkdir -p "$LOGS"
for tool in eksctl kubectl aws helm jq envsubst curl; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 1; }
done

echo "Creating 3 clusters at $OLD_VERSION on $NODE_TYPE. Logs: $LOGS/<cluster>.log"
create() { # <cluster> <mode> <node-count>
  KUBECONFIG="$HOME/.kube/$1.config" CLUSTER_NAME="$1" MODE="$2" K8S_VERSION="$OLD_VERSION" \
    NODE_TYPE="$NODE_TYPE" NODE_COUNT="$3" "$SHARED" >"$LOGS/$1.log" 2>&1
}
pids=()
create upg-mng  standard 3 & pids+=($!)
create upg-karp standard 2 & pids+=($!)
create upg-auto auto     0 & pids+=($!)
rc=0
for p in "${pids[@]}"; do wait "$p" || rc=1; done
[ "$rc" = 0 ] || { echo "A cluster failed to create. See $LOGS/*.log" >&2; exit 1; }

echo "==> Prepare the clusters in parallel (load balancer controller / Karpenter / Auto Mode pool)"
prep_mng()  { KUBECONFIG="$HOME/.kube/upg-mng.config"  CLUSTER_NAME=upg-mng  ./scripts/install-lbc.sh; }
prep_karp() {
  export KUBECONFIG="$HOME/.kube/upg-karp.config" CLUSTER_NAME=upg-karp
  ../22-karpenter/scripts/install-karpenter.sh
  ./scripts/install-lbc.sh
  # Pin the AMI release (recommended for production). AMI_ALIAS must be a release that exists for $OLD_VERSION.
  AMI_ALIAS="${AMI_ALIAS:-$(./scripts/ami-release.sh "$OLD_VERSION" latest)}" NODE_TYPE="$NODE_TYPE" \
    envsubst '${CLUSTER_NAME} ${AMI_ALIAS} ${NODE_TYPE}' <manifests/karpenter.yaml | kubectl apply -f -
}
prep_auto() {
  export KUBECONFIG="$HOME/.kube/upg-auto.config" CLUSTER_NAME=upg-auto
  # Auto Mode never launches nano/micro/small sizes and does not offer t9g, so its pool uses AUTO_NODE_TYPE.
  NODE_TYPE="${AUTO_NODE_TYPE:-t4g.medium}" envsubst '${NODE_TYPE}' <manifests/automode-nodepool.yaml | kubectl apply -f -
}
pids=()
prep_mng  >"$LOGS/prep-mng.log"  2>&1 & pids+=($!)
prep_karp >"$LOGS/prep-karp.log" 2>&1 & pids+=($!)
prep_auto >"$LOGS/prep-auto.log" 2>&1 & pids+=($!)
rc=0
for p in "${pids[@]}"; do wait "$p" || rc=1; done
[ "$rc" = 0 ] || { echo "A prepare step failed. See $LOGS/prep-*.log" >&2; exit 1; }

cat <<MSG

All three clusters are ready at $OLD_VERSION. One terminal per cluster:
  source scripts/env.sh mng   && ./scripts/deploy-app.sh
  source scripts/env.sh karp  && ./scripts/deploy-app.sh
  source scripts/env.sh auto  && ./scripts/deploy-app.sh
Delete everything when finished: ./scripts/down-all.sh
MSG
