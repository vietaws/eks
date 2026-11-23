#!/usr/bin/env bash
# Deploy the zero-downtime test app on the cluster selected with `source scripts/env.sh <mng|karp|auto>`.
# Usage: ./scripts/deploy-app.sh [good|bad]       good (default) = hardened, bad = single replica, no PDB, no probe
#
# The Service (and so the NLB and its hostname) is created once and never deleted: both variants share the same
# Service, so switching good <-> bad only rolls the pods and a running probe.sh keeps working.
#
# The good variant also turns on the load balancer pod readiness gate: a new pod counts as Ready only when its NLB
# target is Healthy, so a rollout or a drain never leaves the target group with only Initial/Draining targets.
# The gate is injected at pod creation and only when the Service's TargetGroupBinding already exists, so the
# script applies the Service first, waits for the binding, then applies the Deployment.
set -euo pipefail
cd "$(dirname "$0")/.."
VARIANT="${1:-good}"
CLUSTER_KEY="${CLUSTER_KEY:?run: source scripts/env.sh mng|karp|auto}"
case "$VARIANT" in good) F=manifests/app.yaml ;; bad) F=manifests/app-bad.yaml ;; *) echo "variant: good|bad" >&2; exit 1 ;; esac
case "$CLUSTER_KEY" in
  mng)  export SEL_KEY=kubernetes.io/os        SEL_VAL=linux;        export LB_CLASS=service.k8s.aws/nlb
        GATE_LABEL=elbv2.k8s.aws/pod-readiness-gate-inject ;;      # AWS Load Balancer Controller
  karp) export SEL_KEY=karpenter.sh/nodepool   SEL_VAL=upgrade-demo; export LB_CLASS=service.k8s.aws/nlb
        GATE_LABEL=elbv2.k8s.aws/pod-readiness-gate-inject ;;
  auto) export SEL_KEY=karpenter.sh/nodepool   SEL_VAL=upgrade-demo; export LB_CLASS=eks.amazonaws.com/nlb
        GATE_LABEL=eks.amazonaws.com/pod-readiness-gate-inject ;;  # EKS Auto Mode built-in load balancing
  *) echo "CLUSTER_KEY must be mng, karp or auto" >&2; exit 1 ;;
esac
NS=default
TMP="$(mktemp -d)"; trap 'rm -f "$TMP"/svc.yaml "$TMP"/rest.yaml; rmdir "$TMP" 2>/dev/null || true' EXIT

# Render and split the manifest: the Service goes first, everything else (Deployment, PDB) after it.
envsubst '${SEL_KEY} ${SEL_VAL} ${LB_CLASS}' <"$F" | awk -v svc="$TMP/svc.yaml" -v rest="$TMP/rest.yaml" '
  function flush() { if (doc != "") { print "---" doc > ((doc ~ /\nkind: Service\n/) ? svc : rest) }; doc = "" }
  /^---[[:space:]]*$/ { flush(); next }
  { doc = doc "\n" $0 }
  END { flush() }'

# 1. Readiness gate: on for good, off for bad (the bad variant is the careless baseline).
if [ "$VARIANT" = good ]; then
  kubectl label namespace "$NS" "${GATE_LABEL}=enabled" --overwrite >/dev/null
else
  kubectl label namespace "$NS" "${GATE_LABEL}-" >/dev/null 2>&1 || true
fi

# 2. Service first (unchanged on later runs, so the NLB is kept), then wait for its TargetGroupBinding.
kubectl apply -n "$NS" -f "$TMP/svc.yaml"
echo "Waiting for the TargetGroupBinding of service/web (needed before pods are created for the gate to be injected)..."
TGB=""
for _ in $(seq 1 60); do
  TGB="$(kubectl get targetgroupbindings -n "$NS" -o jsonpath='{range .items[?(@.spec.serviceRef.name=="web")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | head -1 || true)"
  [ -n "$TGB" ] && break; sleep 5
done
[ -n "$TGB" ] || echo "WARN: no TargetGroupBinding yet; pods are created without the readiness gate." >&2

# 3. Deployment (+ PDB for good). apply does not prune, so remove the PDB explicitly for the bad variant.
if [ "$VARIANT" = bad ]; then kubectl delete pdb web -n "$NS" --ignore-not-found; fi
APPLY_OUT="$(kubectl apply -n "$NS" -f "$TMP/rest.yaml")"; echo "$APPLY_OUT"

# Pods created before the label or the binding existed have no gate. A changed template rolls the pods anyway;
# an unchanged one does not, so restart only in that case.
if [ "$VARIANT" = good ] && [ -n "$TGB" ] && grep -q '^deployment.apps/web unchanged' <<<"$APPLY_OUT"; then
  GATES="$(kubectl get pods -n "$NS" -l app=web -o jsonpath='{range .items[*]}{.spec.readinessGates[*].conditionType}{"\n"}{end}' 2>/dev/null || true)"
  if [ -z "$GATES" ] || printf '%s\n' "$GATES" | grep -qv 'target-health'; then
    echo "Some web pods have no readiness gate yet: restarting the Deployment (rolling, PDB protected)."
    kubectl rollout restart deployment/web -n "$NS"
  fi
fi

# With the gate, Ready also waits for the NLB health checks, so allow up to 10 minutes.
if ! kubectl rollout status deployment/web -n "$NS" --timeout=600s; then
  echo "Pods did not become ready in 10 minutes. Check:" >&2
  echo "  kubectl get pods -l app=web -o wide          (READINESS GATES 0/1 = NLB target not Healthy yet)" >&2
  echo "  kubectl get nodeclaims; kubectl describe nodepool upgrade-demo" >&2
  echo "Auto Mode cannot launch t9g or any nano/micro/small size: use AUTO_NODE_TYPE=t4g.medium for upg-auto." >&2
  exit 1
fi
kubectl get pods -n "$NS" -l app=web -o wide

echo "Waiting for the NLB hostname..."
LB=""
for _ in $(seq 1 60); do
  LB="$(kubectl get svc web -n "$NS" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  [ -n "$LB" ] && break; sleep 10
done
[ -n "$LB" ] || { echo "No load balancer hostname yet. Check: kubectl describe svc web" >&2; exit 1; }
echo "URL: http://$LB"
echo "Probe it (the hostname stays the same across good/bad switches): ./scripts/probe.sh http://$LB 0.2 1"
