# 22 — Karpenter Node Autoscaling

## 🎯 Scenario
Replace node group + Cluster Autoscaler with **Karpenter**: a just-in-time node provisioner that talks to the
EC2 API directly, picks the cheapest instance that fits the pending pods, and consolidates to save cost.

> ✅ Targets **Karpenter 1.15.x** (stable `karpenter.sh/v1` API) on **EKS 1.37**, with the **AL2023** AMI
> family and **EKS Pod Identity**. 1.15.x supports Kubernetes 1.36 and 1.37 (see the
> [compatibility matrix](https://karpenter.sh/docs/upgrading/compatibility/)).

## 🗺️ Sub-demos
| Step | Folder | Teaches |
|------|--------|---------|
| 1 | `01-configure` | Intro, components, Spot handling, install (CloudFormation + Pod Identity + Helm) |
| 2 | `02-implement` | EC2NodeClass + NodePool, first nodes |
| 3 | `03-consolidation` | Bin-pack and remove under-used nodes to cut cost |
| 4 | `04-drift` | Replace nodes when the NodePool, EC2NodeClass or AMI changes |
| 5 | `05-expired` | Node expiry (`expireAfter`) for freshness |

## ✅ Prerequisites
- `eksctl` ≥ 0.230.0, `kubectl`, `helm`, `aws` CLI, `envsubst` (`brew install gettext`); optional `eks-node-viewer`.
- The shared cluster from `02-create-eks-cluster` (`MODE=standard`): OIDC, Pod Identity agent, a public node
  group and `karpenter.sh/discovery` tags are already set up there.

## 🚀 Steps
```bash
export AWS_REGION=ap-southeast-1 CLUSTER_NAME=eksdemo
(cd ../02-create-eks-cluster && ./scripts/up.sh --mode=standard)    # cluster, about 15-20 min
./scripts/install-karpenter.sh                                    # Karpenter 1.15.3
```
Then follow `02-implement` → `03-consolidation` → `04-drift` → `05-expired`. Upgrading a cluster that runs Karpenter is
covered once, for all compute types, in `../33-cluster-upgrade`.

## 🔍 Validation
```bash
kubectl get nodepool,ec2nodeclass,nodeclaims
kubectl logs -f -n kube-system -l app.kubernetes.io/name=karpenter -c controller
```

## 🧹 Cleanup
```bash
(cd ../02-create-eks-cluster && ./scripts/down.sh --cluster-name=eksdemo)
```
`down.sh` removes the NodePools and their nodes, the Helm release, launch templates and the
`Karpenter-<cluster>` CloudFormation stack before it deletes the cluster.

## 📝 Notes & cost
- **Why Karpenter over Cluster Autoscaler:** no ASG round trip, no per-variant node groups, native bin-packing,
  built-in Spot handling, consolidation.
- Biggest cost levers: allow **Spot + on-demand**, allow **amd64 + arm64** (Graviton), and use
  `consolidationPolicy: WhenEmptyOrUnderutilized` (or `Balanced`).
- Karpenter is **self-managed**: you upgrade it, keep it compatible with your Kubernetes version, and run it on
  nodes that it does not manage. `../32-auto-mode` shows the AWS-managed alternative.
- ⚠️ **Not tested against a live AWS account.** Manifests validate against the Karpenter 1.15.3 CRD schemas,
  and the script passes `shellcheck`. Report any behavior that differs from these READMEs.
