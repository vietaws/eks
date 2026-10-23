# 22.02 — Implement Karpenter (NodePool + EC2NodeClass)

## 🎯 Scenario
Create a Karpenter **NodePool** and **EC2NodeClass**, then watch Karpenter launch
right-sized nodes directly via the EC2 API when pods go pending.

> ✅ Uses the **stable `karpenter.sh/v1` API** (GA since Karpenter v1.0) and the
> **AL2023** AMI family. The older `v1beta1` API and `AL2` AMI family are
> deprecated.

## 🗺️ Architecture
```
Pending pods → Karpenter → EC2 API → launch node (from NodePool + EC2NodeClass)
```

## ✅ Prerequisites
- Karpenter installed (see `01-configure/04-install.md`).
- `CLUSTER_NAME` exported; subnets/SGs tagged `karpenter.sh/discovery=<cluster>`.

## 🚀 Steps
```bash
# 1. Create the EC2NodeClass (v1) and NodePool (v1)
kubectl apply -f nodeclass.yaml      # EC2NodeClass (karpenter.k8s.aws/v1)

cat <<EOF | envsubst | kubectl apply -f -
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64", "arm64"]      # allow Graviton for cost savings
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]   # Spot-first, fall back to on-demand
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["c", "m", "r"]
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["2"]
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      expireAfter: 720h
  limits:
    cpu: 1000
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized   # v1 name (was WhenUnderutilized)
    consolidateAfter: 1m
EOF

# 2. Scale a demo app to force node provisioning
kubectl apply -f manifests/app.yaml
kubectl scale deployment inflate --replicas 5
```

## 🔍 Validation
```bash
kubectl get nodepool,ec2nodeclass
kubectl logs -f -n kube-system -l app.kubernetes.io/name=karpenter -c controller
kubectl get nodes -w
```

## 🧹 Cleanup
```bash
kubectl delete deployment inflate
kubectl delete nodepool default
kubectl delete ec2nodeclass default
```

## 📝 Notes & cost
- **v1 API changes vs v1beta1:** `apiVersion: karpenter.sh/v1`,
  `nodeClassRef` now uses `group`/`kind`/`name`, `consolidationPolicy:
  WhenEmptyOrUnderutilized`, `expireAfter` moved under the template spec,
  `amiSelectorTerms` is required (use `alias: al2023@latest`).
- Allowing both `amd64` + `arm64` and `spot` + `on-demand` lets Karpenter pick
  the cheapest instance that fits — the core cost win.
