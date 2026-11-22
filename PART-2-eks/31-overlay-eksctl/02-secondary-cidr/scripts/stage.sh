#!/usr/bin/env bash
# Move the cluster to the next stage by replacing the node group (AWS recommends new nodes, not a rolling
# update of existing ones, when switching between single IPs and prefixes).
#   stage 1: custom networking (pods in the secondary CIDR), maxPods MAX_PODS_STAGE1 -> <prefix>1 replaces <prefix>0
#   stage 2: + prefix delegation, maxPods MAX_PODS_STAGE2                             -> <prefix>2 replaces <prefix>1
# Names come from ../config.env. Usage: ./scripts/stage.sh <1|2> [aws-profile]  (no profile = default AWS profile)
set -euo pipefail

# shellcheck source=SCRIPTDIR/../../lib/common.sh
. "$(dirname "$0")/../../lib/common.sh"
STAGE="${1:-}"
case "$STAGE" in
  1 | 2) ;;
  *) echo "usage: $0 <1|2> [aws-profile]" >&2; exit 2 ;;
esac
PREV=$((STAGE - 1))

load_config
require_tools eksctl kubectl aws python3
use_profile "${2:-}"
render

echo "==> 1/3 vpc-cni add-on settings for stage $STAGE (applied BEFORE the new nodes start)"
eksctl update addon -f "$RENDER_DIR/addons-s${STAGE}.yaml" --wait

echo "==> 2/3 New node group ${NODEGROUP_PREFIX}${STAGE}"
if nodegroup_exists "${NODEGROUP_PREFIX}${STAGE}"; then
  echo "    node group ${NODEGROUP_PREFIX}${STAGE} already exists, skipping"
else
  eksctl create nodegroup -f "$RENDER_DIR/nodegroup-s${STAGE}.yaml"
fi

echo "==> 3/3 Drain and delete the old node group ${NODEGROUP_PREFIX}${PREV}"
if nodegroup_exists "${NODEGROUP_PREFIX}${PREV}"; then
  eksctl delete nodegroup --cluster "$CLUSTER_NAME" --name "${NODEGROUP_PREFIX}${PREV}" --drain --wait
else
  echo "    node group ${NODEGROUP_PREFIX}${PREV} not found, skipping"
fi

echo "Stage $STAGE ready."
kubectl get nodes -o custom-columns=NAME:.metadata.name,MAX_PODS:.status.allocatable.pods
