# 22.06 — Spot cost and availability

## 🎯 Scenario
Prove two things with a real app instead of `pause` pods:
1. **Cost:** Karpenter runs the workload on Spot and the cluster costs a fraction of the On-Demand price.
2. **Availability:** the app keeps answering while nodes are replaced (drift, consolidation) and even when a Spot
   node is reclaimed, as long as it has replicas, a PDB and a readiness probe. Without them it goes down.

> This demo scales and replaces **nodes**. It does not upgrade the EKS control plane (see `../../33-cluster-upgrade`).

## 🗺 Architecture
```
prober (managed node group) ──► Service web ──► 4 × web pods on Karpenter Spot nodes
   counts ok / FAIL every 0.2 s                       ▲
                                  Karpenter ──────────┘ launch Spot, consolidate, replace on drift / interruption
```

## ✅ Prerequisites
- Karpenter, the `default` EC2NodeClass and NodePool from `../02-implement` (it allows `spot` and `on-demand`).
- `jq`, `awk`, `aws`, `kubectl`. Optional: [`eks-node-viewer`](https://github.com/awslabs/eks-node-viewer) for a live `$/hour` view.
- IAM for the scripts: `pricing:GetProducts`, `ec2:DescribeSpotPriceHistory`. The interruption script also needs FIS and IAM role permissions.

## 🚀 Steps
### 1. Deploy the app and the probe
```bash
kubectl apply -f manifests/web.yaml -f manifests/prober.yaml
kubectl rollout status deployment/web deployment/prober
kubectl get pods -l app=web -o wide                    # all on Karpenter nodes
kubectl get nodes -L karpenter.sh/capacity-type,node.kubernetes.io/instance-type,kubernetes.io/arch
```
Expected: 4 `web` pods Running on new nodes with `capacity-type=spot`. The prober starts printing `ok=… fail=0`.

### 2. Show the saving
```bash
./scripts/cost-report.sh          # or: ./scripts/cost-report.sh --region=ap-southeast-1
```
The script prints each Karpenter node with its Spot price now and its On-Demand price, then the hourly and monthly totals and the saving percentage.
Spot prices change over time and by zone, so the exact percentage differs per run; it is normally well above 50%.

### 3. Availability while nodes are replaced (protected app)
Force Karpenter to replace every node by changing a NodePool label (label changes cause drift):
```bash
kubectl logs deploy/prober --tail=2                    # note ok=... fail=0
kubectl patch nodepool default --type merge -p '{"spec":{"template":{"metadata":{"labels":{"demo":"round1"}}}}}'
kubectl get nodeclaims -w                              # replacements appear first, then old nodes go away
kubectl get pdb web                                    # ALLOWED DISRUPTIONS stays at 1 or more
```
After the roll finishes (a few minutes):
```bash
kubectl logs deploy/prober | grep -c FAIL              # expected 0 (or a very small number)
kubectl logs deploy/prober --tail=1
```
Why it holds: Karpenter launches the replacement node **before** it drains the old one, the PDB lets only 1 pod leave at a
time, the readiness probe keeps traffic off pods that are not ready, and `preStop` lets in-flight requests finish.

### 4. See downtime (unprotected app)
```bash
kubectl delete -f manifests/web.yaml
kubectl apply -f manifests/web-no-protection.yaml      # 1 replica, no PDB, no preStop, no readiness probe
kubectl rollout status deployment/web
kubectl delete pod -l app=prober                       # restart the counter
kubectl patch nodepool default --type merge -p '{"spec":{"template":{"metadata":{"labels":{"demo":"round2"}}}}}'
kubectl get nodeclaims -w
kubectl logs deploy/prober | grep FAIL                 # expected: a burst of FAIL lines while the only pod moves
```
The single pod is evicted from the old node and must start again on the new one, so requests fail in between.
Restore the protected app: `kubectl delete -f manifests/web-no-protection.yaml && kubectl apply -f manifests/web.yaml`.

### 5. Survive a Spot interruption (optional)
```bash
kubectl delete pod -l app=prober                       # restart the counter
./scripts/simulate-spot-interruption.sh                # asks for 'yes'; uses AWS FIS to send a real 2-minute notice
kubectl get nodes -L karpenter.sh/capacity-type -w     # the node gets tainted, a replacement appears, the old node goes
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter -c controller | grep -iE 'interrupt|spot'
kubectl logs deploy/prober | grep -c FAIL
```
A Spot interruption is **involuntary**: it ignores the PDB and the budgets. The app survives because it has 4 replicas on
several nodes, so only the pods on the lost node restart, and the Service keeps sending traffic to the others.

## 🔍 Validation
| Check | Command | Expected |
|-------|---------|----------|
| App runs on Spot | `kubectl get nodes -L karpenter.sh/capacity-type` | `spot` on Karpenter nodes |
| Saving | `./scripts/cost-report.sh` | Total now is clearly below On-Demand |
| No downtime (protected) | `kubectl logs deploy/prober \| grep -c FAIL` | 0 or close to 0 |
| Downtime (unprotected) | same command after step 4 | Several FAIL lines |
| Interruption handled | Karpenter log and `kubectl get nodeclaims` | New NodeClaim launched, old one deleted |

## 🧹 Cleanup
```bash
kubectl delete -f manifests/web.yaml -f manifests/prober.yaml --ignore-not-found
kubectl delete -f manifests/web-no-protection.yaml --ignore-not-found
kubectl patch nodepool default --type merge -p '{"spec":{"template":{"metadata":{"labels":{"demo":null}}}}}'
```
The simulation script removes its own FIS role and template. If it was interrupted, delete the role `karpenter-demo-fis-<cluster>` and the FIS experiment template by hand.

## ✅ Conclusion
- Spot plus a flexible NodePool is the largest single saving: the same pods run for a fraction of the On-Demand price.
- Zero downtime is a property of the **workload**, not of Karpenter: replicas, spread, readiness probe, PDB and `preStop`.
  Karpenter supplies the safe order (replacement first, then drain) and respects PDBs for voluntary disruption.
- Spot interruptions are the one case where a PDB cannot help, so keep at least 2 replicas on different nodes and
  run work that cannot be interrupted on an On-Demand pool.

## 📝 Notes
- ⚠ Not tested against a live AWS account. The manifests parse as valid YAML, the scripts pass `shellcheck`, and the price parsing was checked with sample data. The FIS experiment (`aws:ec2:send-spot-instance-interruptions`) and the Pricing API filters should be confirmed on the first run.
- `vietaws/eks:home` is a multi-arch image (amd64 + arm64) listening on port 8080, shared with `../../33-cluster-upgrade`.
- Spot-to-Spot **replacement** consolidation is off by default (`SpotToSpotConsolidation` feature gate, 15+ instance types needed). Spot **delete** consolidation works without it.
