#!/usr/bin/env bash
# shellcheck shell=bash disable=SC2317
# Source this file, one terminal per cluster:   source scripts/env.sh mng|karp|auto
# It selects the cluster and gives that terminal its own kubeconfig, so three clusters can run in parallel
# without fighting over ~/.kube/config.
_target="${1:-}"
case "$_target" in
  mng)  export CLUSTER_NAME=upg-mng  CLUSTER_MODE=standard ;;
  karp) export CLUSTER_NAME=upg-karp CLUSTER_MODE=standard ;;
  auto) export CLUSTER_NAME=upg-auto CLUSTER_MODE=auto ;;
  *) echo "usage: source scripts/env.sh mng|karp|auto" >&2; return 1 2>/dev/null || exit 1 ;;
esac
export CLUSTER_KEY="$_target"
export AWS_REGION="${AWS_REGION:-ap-southeast-1}"
export OLD_VERSION="${OLD_VERSION:-1.36}"
export NEW_VERSION="${NEW_VERSION:-1.37}"
export NODE_TYPE="${NODE_TYPE:-t9g.medium}"      # Auto Mode rejects t9g: its pool uses AUTO_NODE_TYPE (default t4g.medium)
export KUBECONFIG="$HOME/.kube/${CLUSTER_NAME}.config"
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
export DEMO_DIR
echo "cluster=$CLUSTER_NAME mode=$CLUSTER_MODE region=$AWS_REGION node=$NODE_TYPE kubeconfig=$KUBECONFIG"
unset _target
