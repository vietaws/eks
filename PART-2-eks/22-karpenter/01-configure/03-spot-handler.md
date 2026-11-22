# Spot and interruption handling

## Why Spot
Spot instances cost up to about 90% less than On-Demand, but EC2 can take them back with a **2-minute warning**.
Karpenter makes Spot practical for stateless workloads: it launches from many instance types at once and replaces an interrupted node before it disappears.

## How interruption handling works
```
EC2 Spot interruption warning (2 min)  ─┐
EC2 rebalance recommendation            ├─► Amazon EventBridge rules ─► SQS queue "<cluster>" ─► Karpenter
Scheduled change / instance health      ─┘
Karpenter: taint the node (karpenter.sh/disrupted:NoSchedule) ─► launch a replacement ─► drain ─► delete
```
- The CloudFormation stack (`Karpenter-<cluster>`) creates the SQS queue and the EventBridge rules.
- Karpenter is told the queue name through the Helm value `settings.interruptionQueue` (the `INTERRUPTION_QUEUE`
  setting). If it is empty, interruption handling is **off**.
- The controller needs the `KarpenterControllerInterruptionPolicy` (attached by the install script).
- Interruptions are **involuntary**: they ignore PDBs and disruption budgets. Two minutes is all the drain gets.

## How Karpenter picks the instance
| Order | Capacity type | Rule |
|-------|---------------|------|
| 1 | Spot | Chosen with `price-capacity-optimized`: cheap **and** from a deep capacity pool. The very cheapest type is skipped if its pool is small |
| 2 | On-Demand | Used when Spot is not allowed, has no capacity, or the NodePool lists only `on-demand` |

Both are allowed when the NodePool has `karpenter.sh/capacity-type In [spot, on-demand]`.

## Spot consolidation
- **Delete** consolidation (remove a Spot node, pods fit on other nodes) is on by default.
- **Replace** consolidation (swap a Spot node for a cheaper Spot node) needs the `SpotToSpotConsolidation`
  feature gate (default `false`) and at least 15 candidate instance types, to avoid a race to the cheapest, riskiest pool.

## Make a workload survive an interruption
| Control | Purpose |
|---------|---------|
| 2 or more replicas, spread across nodes and zones | One lost node never removes the whole service |
| `preStop` delay and a short `terminationGracePeriodSeconds` (under 120 s) | Finish in-flight requests inside the 2-minute window |
| Readiness probe | Traffic only goes to ready pods, including the replacements |
| PodDisruptionBudget | Protects against voluntary disruption (consolidation, drift, expiry), not against Spot reclaim |
| On-Demand fallback or a separate On-Demand NodePool | For work that cannot tolerate interruption |

The hands-on proof (cost report, zero-downtime check, simulated Spot interruption) is in `../06-spot-availability`.
