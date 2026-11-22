#!/usr/bin/env bash
# Cluster-side view of an upgrade, sampled every INTERVAL seconds and appended to a CSV. Shows WHY a probe failed:
# control plane version, node count by version, ready/pending pods, ready endpoints behind the Service, and how
# many disruptions the PDB still allows. Needs: kubectl, jq, aws (for the control plane version).
#
# Usage: source scripts/env.sh <mng|karp|auto>; ./scripts/watch-upgrade.sh [interval-seconds]
# A line is flagged "!!" when ready endpoints < MIN_ENDPOINTS (default 2): the Service had too little capacity.
set -uo pipefail
INTERVAL="${1:-5}"
MIN_ENDPOINTS="${MIN_ENDPOINTS:-2}"
: "${CLUSTER_NAME:?run: source scripts/env.sh mng|karp|auto}"
for tool in kubectl jq aws; do command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 1; }; done
CSV="watch-${CLUSTER_NAME}-$(date -u +%Y%m%dT%H%M%S).csv"
echo "time,control_plane,nodes,nodes_by_version,web_available,web_ready_endpoints,pods_pending,pdb_allowed,nodeclaims,flag" >"$CSV"
echo "Sampling every ${INTERVAL}s into $CSV (Ctrl-C to stop)"
MIN_SEEN=999
trap 'echo; echo "lowest ready endpoint count seen: $MIN_SEEN (alert threshold $MIN_ENDPOINTS)"; exit 0' INT TERM
while true; do
  NOW="$(date -u +%H:%M:%S)"
  CP="$(aws eks describe-cluster --name "$CLUSTER_NAME" --query 'cluster.[version,status]' --output text 2>/dev/null | tr '\t' '/')"
  NODES_JSON="$(kubectl get nodes -o json 2>/dev/null || echo '{"items":[]}')"
  NODES="$(jq '.items|length' <<<"$NODES_JSON")"
  BYVER="$(jq -r '[.items[].status.nodeInfo.kubeletVersion|split("-")[0]]|group_by(.)|map("\(.[0])x\(length)")|join(" ")' <<<"$NODES_JSON")"
  AVAIL="$(kubectl get deploy web -o jsonpath='{.status.availableReplicas}' 2>/dev/null)"; AVAIL="${AVAIL:-0}"
  EP="$(kubectl get endpointslices -l kubernetes.io/service-name=web -o json 2>/dev/null |
        jq '[.items[].endpoints[]?|select(.conditions.ready==true)]|length' 2>/dev/null)"; EP="${EP:-0}"
  PEND="$(kubectl get pods -A --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  PDB="$(kubectl get pdb web -o jsonpath='{.status.disruptionsAllowed}' 2>/dev/null)"; PDB="${PDB:--}"
  NC="$(kubectl get nodeclaims --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  FLAG=""
  [ "$EP" -lt "$MIN_ENDPOINTS" ] && FLAG="!!"
  [ "$EP" -lt "$MIN_SEEN" ] && MIN_SEEN=$EP
  echo "$NOW,$CP,$NODES,$BYVER,$AVAIL,$EP,$PEND,$PDB,$NC,$FLAG" >>"$CSV"
  printf '%s cp=%s nodes=%s [%s] web_avail=%s endpoints=%s pending=%s pdb_allowed=%s nodeclaims=%s %s\n' \
    "$NOW" "$CP" "$NODES" "$BYVER" "$AVAIL" "$EP" "$PEND" "$PDB" "$NC" "$FLAG"
  sleep "$INTERVAL"
done
