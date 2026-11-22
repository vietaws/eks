#!/usr/bin/env bash
# Deploy the zero-downtime test app on the cluster selected with `source scripts/env.sh <mng|karp|auto>`.
# Usage: ./scripts/deploy-app.sh [good|bad]       good (default) = hardened, bad = single replica, no PDB, no probe
set -euo pipefail
cd "$(dirname "$0")/.."
VARIANT="${1:-good}"
CLUSTER_KEY="${CLUSTER_KEY:?run: source scripts/env.sh mng|karp|auto}"
case "$VARIANT" in good) F=manifests/app.yaml ;; bad) F=manifests/app-bad.yaml ;; *) echo "variant: good|bad" >&2; exit 1 ;; esac
case "$CLUSTER_KEY" in
  mng)  export SEL_KEY=kubernetes.io/os        SEL_VAL=linux;       export LB_CLASS=service.k8s.aws/nlb ;;
  karp) export SEL_KEY=karpenter.sh/nodepool   SEL_VAL=upgrade-demo; export LB_CLASS=service.k8s.aws/nlb ;;
  auto) export SEL_KEY=karpenter.sh/nodepool   SEL_VAL=upgrade-demo; export LB_CLASS=eks.amazonaws.com/nlb ;;
esac
kubectl delete -f manifests/app.yaml -f manifests/app-bad.yaml --ignore-not-found --wait=true >/dev/null 2>&1 || true
envsubst '${SEL_KEY} ${SEL_VAL} ${LB_CLASS}' <"$F" | kubectl apply -f -
if ! kubectl rollout status deployment/web --timeout=420s; then
  echo "Pods did not become ready in 7 minutes. If no node was launched for $NODE_TYPE on this cluster, check" >&2
  echo "  kubectl get nodeclaims; kubectl describe nodepool upgrade-demo" >&2
  echo "and re-create all three clusters with NODE_TYPE=t4g.small so the comparison stays fair." >&2
  exit 1
fi
echo "Waiting for the NLB hostname..."
for _ in $(seq 1 60); do
  LB="$(kubectl get svc web -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  [ -n "$LB" ] && break; sleep 10
done
[ -n "${LB:-}" ] || { echo "No load balancer hostname yet. Check: kubectl describe svc web" >&2; exit 1; }
echo "URL: http://$LB"
echo "Wait 2-3 minutes for the targets to turn healthy, then: ./scripts/probe.sh http://$LB"
