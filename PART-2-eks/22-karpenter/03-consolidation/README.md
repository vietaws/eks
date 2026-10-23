# 22.03 — Karpenter Consolidation

## 🎯 Scenario
Watch Karpenter **consolidate** workloads: it removes underutilized nodes and
repacks pods onto fewer/cheaper nodes to save money — automatically.

## 🗺️ Architecture
```
Scale up → Karpenter adds nodes (Spot, mixed sizes)
Scale down → Karpenter drains + removes under-utilized nodes → fewer nodes
```

## ✅ Prerequisites
- Karpenter v1.x installed (`01-configure`).
- A default NodePool + EC2NodeClass (`02-implement`).

## 🚀 Steps
Use a NodePool with consolidation enabled (v1 API):
```bash
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
          values: ["amd64", "arm64"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]
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
    consolidationPolicy: WhenEmptyOrUnderutilized   # v1 (replaces WhenUnderutilized)
    consolidateAfter: 1m
EOF

kubectl apply -f manifests/app.yaml
kubectl scale deployment inflate --replicas 8
# then later
kubectl scale deployment inflate --replicas 2    # watch consolidation kick in
```

## 🔍 Validation
```bash
# eks-node-viewer is great here to see $/hour drop as nodes consolidate
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
- `consolidationPolicy` values in **v1**: `WhenEmpty` or
  `WhenEmptyOrUnderutilized`. (`WhenUnderutilized` was renamed.)
- `consolidateAfter` is now a required, explicit duration in v1.
- This is Karpenter's biggest cost lever — combined with Spot + Graviton it
  typically beats a static node group or Cluster Autoscaler.
