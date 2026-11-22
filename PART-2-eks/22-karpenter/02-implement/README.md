# 22.02 — Implement Karpenter (NodePool + EC2NodeClass)

## 🎯 Scenario
Create a Karpenter **EC2NodeClass** and **NodePool**, then watch Karpenter launch right-sized
nodes directly through the EC2 API when pods go pending.

> ✅ Uses the stable **`karpenter.sh/v1`** and **`karpenter.k8s.aws/v1`** APIs (Karpenter 1.x) and the
> **AL2023** AMI family. The `v1beta1` API and the `AL2` family are deprecated.

## 🗺 Architecture
```
Pending pods → Karpenter → EC2 API → launch node (shape from NodePool, AWS settings from EC2NodeClass)
```

## ✅ Prerequisites
- Cluster from `02-create-eks-cluster` (`MODE=standard`) and Karpenter installed (`01-configure/04-install.md`).
- `envsubst` (`brew install gettext`) and `kubectl`.

## 🚀 Steps
```bash
export CLUSTER_NAME=eksdemo
export AMI_ALIAS="al2023@latest"      # newest EKS-optimized AL2023 AMI for the cluster's Kubernetes version

# 1. EC2NodeClass (AWS settings) and NodePool (what to launch)
envsubst < manifests/ec2nodeclass.yaml | kubectl apply -f -
kubectl apply -f manifests/nodepool.yaml

# 2. Wait until both are Ready
kubectl get ec2nodeclass,nodepool

# 3. Force node provisioning with a pending workload (1 vCPU per pod)
kubectl apply -f manifests/app.yaml
kubectl scale deployment inflate --replicas 5
```

## 🔍 Validation
```bash
kubectl get nodeclaims -o wide                       # one NodeClaim per node Karpenter launched
kubectl get nodes -L karpenter.sh/capacity-type,node.kubernetes.io/instance-type,kubernetes.io/arch
kubectl logs -f -n kube-system -l app.kubernetes.io/name=karpenter -c controller
```
Expected: within about a minute the `inflate` pods are Running on new Spot nodes that are **not** part of
the managed node group, and the log shows `launched nodeclaim` / `registered nodeclaim`.

## 🧹 Cleanup
```bash
kubectl delete deployment inflate
kubectl delete nodepool default       # Karpenter drains and terminates its nodes
kubectl delete ec2nodeclass default
```

## 📝 Notes & cost
- **What changed from v1beta1:** `nodeClassRef` is `group`/`kind`/`name`; `expireAfter` moved under
  `spec.template.spec`; the consolidation policy is `WhenEmptyOrUnderutilized` (was `WhenUnderutilized`);
  `amiSelectorTerms` is required (use `alias: al2023@latest` or a pinned `al2023@v20xxxxxx`).
- Allowing both `amd64` + `arm64` and `spot` + `on-demand` lets Karpenter pick the cheapest instance that fits.
  That is the core cost lever.
- `limits.cpu: 100` caps the pool. Remove or raise it only on purpose.
- Karpenter is **self-managed**: you own its upgrades and its IAM. `32-auto-mode` shows the managed alternative.
