# 22.03 — Karpenter Consolidation

## 🎯 Scenario
Watch Karpenter **consolidate**: it removes empty or under-used nodes and repacks pods onto fewer or
cheaper nodes, automatically.

## 🗺 Architecture
```
Scale up   → Karpenter adds nodes (Spot, mixed sizes)
Scale down → Karpenter drains and removes under-used nodes, or replaces them with a cheaper one
```

## ✅ Prerequisites
- Karpenter 1.x installed (`../01-configure/04-install.md`).
- The `default` EC2NodeClass and NodePool from `../02-implement` (the NodePool already sets
  `consolidationPolicy: WhenEmptyOrUnderutilized`, `consolidateAfter: 1m` and a 10% disruption budget).
- Optional: [`eks-node-viewer`](https://github.com/awslabs/eks-node-viewer) to watch `$/hour` drop.

## 🚀 Steps
```bash
kubectl apply -f manifests/app.yaml
kubectl scale deployment inflate --replicas 8
kubectl get nodeclaims -w                      # note how many nodes and which instance types

# later: scale down, but not to zero, so nodes are under-used rather than empty
kubectl scale deployment inflate --replicas 2
```
Watch the log line `disrupting nodeclaim(s) via delete` or `via replace` in the controller log.

### Compare the policies
Edit the pool and repeat the scale-down to see the difference:
```bash
kubectl patch nodepool default --type merge -p '{"spec":{"disruption":{"consolidationPolicy":"WhenEmpty"}}}'
```
| `consolidationPolicy` | Removes empty nodes | Repacks/replaces under-used nodes | Use for |
|-----------------------|---------------------|-----------------------------------|---------|
| `WhenEmpty` | yes | no | Stateful or batch work that you do not want moved |
| `Balanced` | yes | only when the saving outweighs the disruption | Most of the savings with less churn |
| `WhenEmptyOrUnderutilized` (default) | yes | yes | Stateless services, lowest cost |

### Protect a node or a pod
```bash
kubectl annotate node <node> karpenter.sh/do-not-disrupt=true     # blocks voluntary disruption of the node
```
Set the same annotation on a pod (`metadata.annotations`) to protect the node while that pod runs.

## 🔍 Validation
```bash
kubectl logs -f -n kube-system -l app.kubernetes.io/name=karpenter -c controller
kubectl get nodes -w
```
Expected: after `consolidateAfter` (1 minute) plus drain time, node count drops, and the 2 remaining pods
run on fewer nodes.

## 🧹 Cleanup
```bash
kubectl delete deployment inflate
```
Keep the NodePool for the next demos, or run the cleanup in `../02-implement/README.md`.

## 📝 Notes & cost
- `consolidationPolicy` in v1: `WhenEmpty`, `WhenEmptyOrUnderutilized` or `Balanced` (`WhenUnderutilized` was
  renamed). See the [disruption docs](https://karpenter.sh/docs/concepts/disruption/).
- `consolidateAfter` is how long a node must be empty or under-used before Karpenter acts. Set it to `Never`
  to switch consolidation off.
- `disruption.budgets` caps how many nodes are disrupted at once. A budget of `nodes: "0"` freezes all
  voluntary disruption, including drift and expiry, which is useful during business hours or an upgrade window.
- Pods with no controller, `do-not-disrupt` annotations, or a PDB with `maxUnavailable: 0` block consolidation.
- Combined with Spot and Graviton this is Karpenter's biggest cost saving over a static node group.
