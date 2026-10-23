# 22 — Karpenter Node Autoscaling

## 🎯 Scenario
Replace node-group + Cluster Autoscaler with **Karpenter**: a just-in-time node provisioner that talks to the EC2 API directly, picks the cheapest instance that fits pending pods, and consolidates to save cost.

> ✅ This section targets **Karpenter v1.x** (stable `karpenter.sh/v1` API) with the **AL2023** AMI family and **EKS Pod Identity** for auth.

## 🗺️ Sub-demos
| Step | Folder | Teaches |
|------|--------|---------|
| 1 | `01-configure` | Intro, components, Spot handling, install (Helm + Pod Identity) |
| 2 | `02-implement` | Create NodePool + EC2NodeClass, provision first nodes |
| 3 | `03-consolidation` | Bin-pack / remove underutilized nodes to cut cost |
| 4 | `04-drift` | Node drift detection (config/AMI changes) |
| 5 | `05-expired` / `06-expired` | Node expiry (`expireAfter`) for freshness |

## ✅ Prerequisites
- EKS cluster (Karpenter is version-independent of the cluster).
- `helm`, `eksctl`, `aws` CLI, and optionally `eks-node-viewer`.
- Subnets and security groups tagged `karpenter.sh/discovery=<cluster-name>`.

## 🚀 Steps
Follow the sub-folders in order: `01-configure` → `02-implement` →
`03-consolidation` → `04-drift` → `05/06-expired`.

## 🔍 Validation
```bash
kubectl get nodepool,ec2nodeclass
kubectl logs -f -n kube-system -l app.kubernetes.io/name=karpenter -c controller
```

## 🧹 Cleanup
```bash
kubectl delete nodepool --all
kubectl delete ec2nodeclass --all
helm uninstall karpenter -n kube-system
# then delete the cluster/CloudFormation stack (see 01-configure/04-install.md)
```

## 📝 Notes & cost
- **Why Karpenter over Cluster Autoscaler:** faster provisioning (no ASG round trip), no need for many per-variant node groups, native bin-packing, built-in Spot support, and consolidation.
- Biggest cost levers: allow **Spot + on-demand**, allow **amd64 + arm64** (Graviton), and enable `consolidationPolicy: WhenEmptyOrUnderutilized`.
