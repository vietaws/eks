# 21 — Cluster Autoscaler (classic)

## 🎯 Scenario
Automatically add/remove **EC2 worker nodes** by scaling the node group's Auto Scaling Group when pods can't be scheduled. This is the *classic* node autoscaler; see `22-karpenter` for the modern replacement.

> 💡 For new clusters, prefer **Karpenter** (`22`). It is faster (talks to the EC2 API directly), needs no per-variant node groups, and bin-packs for cost. This demo is kept for understanding the ASG-based approach.

## 🗺️ Architecture
```
Unschedulable pods → Cluster Autoscaler → updates ASG desired count
                   → ASG launches EC2 → nodes join cluster
```

## ✅ Prerequisites
- Managed node group with min/max set and the autoscaler discovery tags
  (`k8s.io/cluster-autoscaler/enabled`, `k8s.io/cluster-autoscaler/<cluster>`).
- Node IAM role has autoscaling permissions (see `02-create-eks-cluster/01-iam`).

## 🚀 Steps
```bash
# 1. Deploy the autoscaler
kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml
kubectl -n kube-system annotate deployment.apps/cluster-autoscaler \
  cluster-autoscaler.kubernetes.io/safe-to-evict="false"

# 2. Edit the deployment: set your cluster name on --node-group-auto-discovery,
#    add --balance-similar-node-groups and --skip-nodes-with-system-pods=false
kubectl -n kube-system edit deployment.apps/cluster-autoscaler

# 3. IMPORTANT: match the autoscaler image to your Kubernetes minor version.
#    For a 1.3x cluster use autoscaler v1.3x.y (see releases).
kubectl -n kube-system set image deployment.apps/cluster-autoscaler \
  cluster-autoscaler=registry.k8s.io/autoscaling/cluster-autoscaler:v1.XY.Z

# 4. Deploy demo app
kubectl apply -f 01-app.yaml
```

## 🔍 Validation
```bash
# Terminal 1: watch the autoscaler
kubectl -n kube-system logs -f deployment.apps/cluster-autoscaler
# Terminal 2: scale out and watch nodes appear
kubectl scale --replicas=30 deploy demo-deployment
kubectl get nodes -o wide -w
```

## 🧹 Cleanup
```bash
kubectl delete -f 01-app.yaml
kubectl delete -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml
```

## 📝 Notes & cost
- Scale-in is deliberately slow (~10-20 min) to avoid thrash.
- The autoscaler image version **must** track your cluster's Kubernetes minor version, or it won't reconcile correctly.
- **Cost:** combine with a Spot node group and `min=0` where possible. Karpenter generally lowers cost further by bin-packing onto right-sized instances.
