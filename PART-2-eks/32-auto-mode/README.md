# 32 — EKS Auto Mode (and how it differs from Karpenter)

## 🎯 Scenario
**EKS Auto Mode** lets AWS run compute, pod networking, load balancing, DNS and block storage for the cluster.
You create the cluster, deploy workloads, and nodes, load balancers and volumes appear. This demo shows what
that means in practice and how it differs from the self-managed Karpenter in `22-karpenter`. Upgrades are compared in
`33-cluster-upgrade`.

> ✅ Targets **EKS 1.37**. Auto Mode is Karpenter-based, so the NodePool API (`karpenter.sh/v1`) looks familiar.

## 🗺️ Sub-demos
| Step | Folder | Teaches |
|------|--------|---------|
| 1 | `01-auto-mode` | Empty cluster, then compute, NLB and EBS with no add-ons installed |
| 2 | `02-vs-karpenter` | Same NodePool on both, comparison table and "which one when" scenarios |

## ✅ Prerequisites
- `eksctl` ≥ 0.230.0, `kubectl`, `aws` CLI, `curl`.
- The shared scripts in `../02-create-eks-cluster` create and delete the cluster (`MODE=auto`). Nothing here
  repeats cluster creation. For the Karpenter side of `02`, use `MODE=standard` and
  `../22-karpenter/scripts/install-karpenter.sh`.

## 🚀 Steps
```bash
export AWS_REGION=ap-southeast-1 CLUSTER_NAME=eksauto
(cd ../02-create-eks-cluster && ./scripts/up.sh --mode=auto)       # about 15-20 min
```
Then follow `01-auto-mode` → `02-vs-karpenter`. The upgrade story (1.36 → 1.37 on managed node groups, Karpenter and
Auto Mode, with downtime and cost numbers) is in `../33-cluster-upgrade`.

## 🔍 Validation
```bash
kubectl get nodepools                      # general-purpose, system
kubectl get nodeclaims,nodes -o wide
```

## 🧹 Cleanup
```bash
(cd ../02-create-eks-cluster && ./scripts/down.sh --cluster-name=eksauto)
```

## 📝 Notes & cost
- Auto Mode adds a **management fee per instance-hour** on top of EC2. See [EKS pricing](https://aws.amazon.com/eks/pricing/).
- ⚠️ **Not tested against a live AWS account.** Manifests and scripts were validated offline. Report any
  behavior that differs from these READMEs.
