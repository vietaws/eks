#!/usr/bin/env bash
# Reset cluster state between lessons/sections WITHOUT deleting the cluster.
# Deletes user workloads in the 'default' namespace and any 'course-*' namespaces.
# Usage: ./scripts/reset.sh
set -euo pipefail

echo "Deleting common workloads in 'default' namespace..."
kubectl delete deploy,rs,sts,ds,po,svc,cm,secret,pvc,ingress,hpa \
  --all -n default --ignore-not-found=true

echo "Deleting any 'course-*' namespaces created during labs..."
for ns in $(kubectl get ns -o name 2>/dev/null | sed 's|namespace/||' | grep '^course-' || true); do
  echo "  - $ns"
  kubectl delete ns "$ns" --ignore-not-found=true
done

echo "Reset complete. Current default-namespace objects:"
kubectl get all -n default
