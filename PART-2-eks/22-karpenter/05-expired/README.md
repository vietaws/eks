# 22.05 — Karpenter Node Expiry (`expireAfter`)

## 🎯 Scenario
Give every node a **maximum lifetime**. When it is reached, Karpenter replaces the node with a fresh one.
This forces AMI refreshes and recycles nodes for security hygiene.


## 🗺 Architecture
```
node launched ── ... ── expireAfter reached ──► replacement launched ──► old node drained ──► terminated
                                                (budgets and PDBs apply until terminationGracePeriod)
```

## ✅ Prerequisites
- Karpenter, EC2NodeClass and NodePool from `../02-implement`.

## Configuration options
```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      expireAfter: 336h           # 14 days, as in ../02-implement. Only s, m, h units are accepted (no "d"); Karpenter default is 720h
      terminationGracePeriod: 48h # hard limit: after this, pods are force-deleted even if a PDB or do-not-disrupt blocks
      # expireAfter: Never        # nodes never expire
```
| Setting | Meaning |
|---------|---------|
| `expireAfter: 336h` | Node is replaced after 14 days (this demo) |
| `expireAfter: 720h` | Node is replaced after 30 days (Karpenter default) |
| `expireAfter: 360h` | Replace after 15 days (stricter patching policy) |
| `expireAfter: Never` | Disable expiry (rely on drift for AMI updates) |
| `terminationGracePeriod` | Upper bound on draining. Without it, a PDB with `maxUnavailable: 0` or a `do-not-disrupt` pod can block an expired node forever |

> `expireAfter` is an **upper bound**, not a guarantee. A node can be consolidated or drifted earlier.
> Expiry is a forceful method: budgets slow it down but do not cancel it once the grace period ends.

## 🚀 Steps (short lifetime to see it happen)
```bash
kubectl apply -f manifests/app.yaml
kubectl scale deployment inflate --replicas 2
kubectl get nodeclaims -w                       # wait for nodes, note their age

# Lower the lifetime to 15 minutes. Changing expireAfter drifts the existing nodes once (they keep the old value)
kubectl patch nodepool default --type merge \
  -p '{"spec":{"template":{"spec":{"expireAfter":"15m","terminationGracePeriod":"5m"}}}}'

# ~15 minutes after the replacement nodes start, they are replaced again
kubectl get nodeclaims -o custom-columns=NAME:.metadata.name,CREATED:.metadata.creationTimestamp
kubectl logs -f -n kube-system -l app.kubernetes.io/name=karpenter -c controller | grep -iE 'expire|disrupt'
```

### Keep workloads off a node that is about to go
Karpenter taints a node being disrupted with `karpenter.sh/disrupted:NoSchedule`, so no new pods land on it.

## 🔍 Validation
```bash
kubectl describe nodeclaim <name> | grep -iE 'expire|Expired|Drifted'
```
Expected: the NodeClaim shows an `Expired` condition, a replacement appears, then the old node is removed.

## 🧹 Cleanup
```bash
kubectl delete deployment inflate
kubectl patch nodepool default --type merge \
  -p '{"spec":{"template":{"spec":{"expireAfter":"336h"}}}}'    # restore the value from ../02-implement (14 days)
```

## ✅ Conclusion
- `expireAfter` caps node lifetime, so every node is eventually replaced by a fresh one on the current AMI.
- It is a safety net behind drift, not a replacement for it. `terminationGracePeriod` stops a blocking PDB from keeping an expired node forever, at the price of force-deleting pods after that time.
- Expiry disrupts like drift, so the same workload protections apply (see `../06-spot-availability`).

## 📝 Notes
- Expiry plus `al2023@latest` is the simplest rolling patch process. For production, pin the AMI alias, promote it through environments, and keep `expireAfter` as the safety net.
- The Kubernetes control plane upgrade path is in `../../33-cluster-upgrade`.
