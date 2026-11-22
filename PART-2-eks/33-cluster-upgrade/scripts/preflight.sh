#!/usr/bin/env bash
# Pre-upgrade checks. Exit code 1 when a BLOCKER is found, 0 otherwise (warnings do not fail the run).
#   BLOCKER: EKS upgrade-readiness insights in ERROR, PDBs that allow zero disruptions, nodes older than the
#            kubelet skew allows, kubectl more than one minor away from the cluster
#   WARN:    single-replica workloads, webhooks with failurePolicy Fail, workloads without a readiness probe,
#            EKS add-ons without a version for the target release
# Usage: source scripts/env.sh <mng|karp|auto>; ./scripts/preflight.sh [target-version]     (default NEW_VERSION)
set -uo pipefail
TARGET="${1:-${NEW_VERSION:-}}"
: "${CLUSTER_NAME:?run: source scripts/env.sh mng|karp|auto}"
[[ "$TARGET" =~ ^1\.[0-9]{2}$ ]] || { echo "usage: $0 <target-version, e.g. 1.37>" >&2; exit 1; }
for tool in kubectl jq aws; do command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 1; }; done
BLOCKERS=0
block() { echo "  BLOCKER: $*"; BLOCKERS=$((BLOCKERS + 1)); }
warn()  { echo "  WARN:    $*"; }
ok()    { echo "  ok:      $*"; }
minor() { sed -E 's/^v?[0-9]+\.([0-9]+).*/\1/' <<<"$1"; }

CUR="$(aws eks describe-cluster --name "$CLUSTER_NAME" --query cluster.version --output text)"
echo "== Cluster $CLUSTER_NAME: $CUR -> $TARGET"
[ $(( $(minor "$TARGET") - $(minor "$CUR") )) -eq 1 ] && ok "one minor version step" || block "EKS upgrades one minor version at a time ($CUR -> $TARGET)"

echo "== 1. EKS upgrade insights"
INS="$(aws eks list-insights --cluster-name "$CLUSTER_NAME" --filter '{"categories":["UPGRADE_READINESS"]}' \
  --query 'insights[].[name,insightStatus.status]' --output text 2>/dev/null || true)"
if [ -z "$INS" ]; then warn "no insights returned (insights refresh about every 24h)"; else
  while IFS=$'\t' read -r name status; do
    case "$status" in ERROR) block "insight '$name' is ERROR (deprecated or removed API in use)" ;;
      WARNING) warn "insight '$name' is WARNING" ;; *) ok "insight '$name' $status" ;; esac
  done <<<"$INS"
fi

echo "== 2. Version skew"
CLIENT="$(kubectl version --client -o json 2>/dev/null | jq -r '.clientVersion.minor' | tr -dc '0-9')"
[ -n "$CLIENT" ] && { d=$(( CLIENT - $(minor "$CUR") )); [ "${d#-}" -le 1 ] && ok "kubectl 1.$CLIENT is within one minor of $CUR" || block "kubectl 1.$CLIENT is more than one minor from $CUR"; }
OLDEST="$(kubectl get nodes -o json | jq -r '[.items[].status.nodeInfo.kubeletVersion|capture("v1\\.(?<m>[0-9]+)").m|tonumber]|min // empty')"
if [ -n "$OLDEST" ]; then
  [ $(( $(minor "$TARGET") - OLDEST )) -le 3 ] && ok "oldest kubelet is 1.$OLDEST (kubelets may lag the API server by up to 3 minors)" \
    || block "oldest kubelet 1.$OLDEST is too old for control plane $TARGET: upgrade nodes first"
fi

echo "== 3. PodDisruptionBudgets that allow zero disruptions (they stall every node upgrade)"
ZERO="$(kubectl get pdb -A -o json | jq -r '.items[]|select(.status.disruptionsAllowed==0)|"\(.metadata.namespace)/\(.metadata.name)"')"
[ -z "$ZERO" ] && ok "none" || while read -r p; do block "PDB $p allows 0 disruptions"; done <<<"$ZERO"

echo "== 4. Single-replica workloads and workloads without a readiness probe (outside kube-system)"
kubectl get deploy,sts -A -o json | jq -r '.items[]|select(.metadata.namespace!="kube-system")|
  select(.spec.replicas==1)|"\(.kind)/\(.metadata.namespace)/\(.metadata.name)"' |
  while read -r w; do warn "$w has 1 replica: it WILL be unavailable while its node drains"; done
kubectl get deploy,sts -A -o json | jq -r '.items[]|select(.metadata.namespace!="kube-system")|
  select([.spec.template.spec.containers[]|has("readinessProbe")]|all|not)|"\(.kind)/\(.metadata.namespace)/\(.metadata.name)"' |
  while read -r w; do warn "$w has a container without a readiness probe"; done

echo "== 5. Webhooks that fail closed (an unavailable webhook blocks pod creation during node replacement)"
{ kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations -o json 2>/dev/null || echo '{"items":[]}'; } |
  jq -r '.items[]|.metadata.name as $n|.webhooks[]?|select(.failurePolicy=="Fail")|"\($n)/\(.name)"' |
  while read -r w; do warn "webhook $w has failurePolicy Fail"; done

echo "== 6. EKS add-ons: version available for $TARGET"
for a in $(aws eks list-addons --cluster-name "$CLUSTER_NAME" --query 'addons[]' --output text 2>/dev/null); do
  CURV="$(aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name "$a" --query addon.addonVersion --output text)"
  NEWV="$(aws eks describe-addon-versions --addon-name "$a" --kubernetes-version "$TARGET" \
    --query 'addons[0].addonVersions[?compatibilities[?defaultVersion==`true`]].addonVersion|[0]' --output text)"
  if [ -z "$NEWV" ] || [ "$NEWV" = None ]; then warn "$a $CURV: no default version for $TARGET"
  elif [ "$NEWV" = "$CURV" ]; then ok "$a $CURV is already the default for $TARGET"
  else echo "  todo:    $a $CURV -> $NEWV (after the control plane upgrade)"; fi
done

echo "== 7. Controllers you run yourself (check their compatibility matrix for $TARGET)"
kubectl get deploy -A -o json | jq -r '.items[]|select(.metadata.name|test("karpenter|aws-load-balancer-controller|cluster-autoscaler|metrics-server"))|
  "\(.metadata.namespace)/\(.metadata.name) image=\(.spec.template.spec.containers[0].image)"' | while read -r l; do echo "  todo:    $l"; done

echo
[ "$BLOCKERS" -eq 0 ] && { echo "RESULT: no blockers. Warnings are risks to accept or fix."; exit 0; } || { echo "RESULT: $BLOCKERS blocker(s). Fix them before upgrading."; exit 1; }
