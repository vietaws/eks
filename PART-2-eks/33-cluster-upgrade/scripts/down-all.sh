#!/usr/bin/env bash
# Delete the three demo clusters in parallel. Asks you to type "delete-all" unless FORCE=1.
# Usage: [AWS_PROFILE=..] [FORCE=1] ./scripts/down-all.sh
set -euo pipefail
cd "$(dirname "$0")/.."
export AWS_REGION="${AWS_REGION:-ap-southeast-1}"
echo "About to DELETE clusters upg-mng, upg-karp and upg-auto in $AWS_REGION (profile ${AWS_PROFILE:-default})."
if [ "${FORCE:-0}" != 1 ]; then
  read -r -p 'Type "delete-all" to confirm: ' CONFIRM
  [ "$CONFIRM" = delete-all ] || { echo "Aborted." >&2; exit 1; }
fi
mkdir -p "${TMPDIR:-/tmp}/upg-logs"
pids=()
for c in upg-mng upg-karp upg-auto; do
  KUBECONFIG="$HOME/.kube/$c.config" CLUSTER_NAME="$c" FORCE=1 ../02-create-eks-cluster/scripts/down.sh \
    >"${TMPDIR:-/tmp}/upg-logs/down-$c.log" 2>&1 & pids+=($!)
done
rc=0
for p in "${pids[@]}"; do wait "$p" || rc=1; done
[ "$rc" = 0 ] || { echo "A delete failed. See ${TMPDIR:-/tmp}/upg-logs/down-*.log and re-run." >&2; exit 1; }
echo "Deleted. The IAM policies AWSLoadBalancerControllerIAMPolicy-upg-* are not removed by eksctl: delete them if you do not need them."
