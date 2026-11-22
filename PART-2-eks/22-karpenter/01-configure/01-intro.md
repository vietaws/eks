# HPA vs Karpenter

HPA (Horizontal Pod Autoscaler) - monitor metrics (cpu, ram, disk) on Deployment and scale if reach

eg: if Pod >= 50% => scale more pod If there is no available resourceon Node => Pod will be pending (unschedule)

=> in this situation, by default we have to provision new EC2 or use Cluster Autoscaler (CA) to increase Node in the Manged Node Group.

The disadvantages of this approach: we have to create many managed node group for different variants such as: compute node group, memory node group, gpu node group or node group by tenant.

## problem with Node AutoScaler - Node provision latency

Pending schedule pods => Cluster Autoscaler (CA) => Update Auto Scaling Group on Amazon EC2 => Using EC2 API => Increase EC2

This process takes minutes to start

With Karpenter:

Pending schedule pods => Using EC2 API => Increase EC2

# What is Karpenter?

- Efficient Node Autoscaler for Kubernetes

- Automatic launch Node without using NodeGroup

- Created by AWS

- Open sourced
  - AWS donated to CNCF
  - Adopted by Azure

# How Karpenter works

```
1. Watch        pods the scheduler marked Unschedulable (Pending)
2. Batch        wait a short window (about 1 s idle, 10 s max) so many pods are handled in one decision
3. Simulate     bin-pack the pods onto candidate instance shapes that satisfy every NodePool rule
                (requirements, limits, taints) and every pod rule (requests, affinity, topology spread)
4. Launch       create a NodeClaim, then call the EC2 CreateFleet API directly with many instance types
                (Spot uses the price-capacity-optimized strategy). No Auto Scaling Group
5. Register     the instance boots, joins the cluster, and the pending pods bind to the new node
6. Disrupt      keep watching: remove empty nodes, repack under-used nodes (consolidation), replace nodes
                that no longer match the spec (drift) or are too old (expireAfter), react to Spot interruptions
```
Everything is driven by two objects: the **NodePool** (what is allowed) and the **EC2NodeClass** (how it is
built on AWS). The controller runs as a normal Deployment on a node it does not manage (here, the managed node group).

# Benefits of Karpenter

| Benefit | How it shows up | Demo |
|---------|-----------------|------|
| Speed | New capacity is requested straight from EC2, no Auto Scaling Group round trip | `02-implement` |
| Cost | Picks the cheapest instance that fits, prefers Spot, repacks and removes idle nodes | `03-consolidation`, `06-spot-availability` |
| Flexibility | One NodePool covers many instance families, sizes, architectures and zones, so no node group per variant | `02-implement` |
| Patching | Drift and `expireAfter` roll nodes to a new AMI with the same disruption controls | `04-drift`, `05-expired` |
| Safety | PDBs, `do-not-disrupt` and disruption budgets limit how much moves at once | `06-spot-availability` |
| Kubernetes native | Plain CRDs (`NodePool`, `EC2NodeClass`, `NodeClaim`), no extra control plane | all |

> ℹ Karpenter scales **nodes**. It does not upgrade the EKS control plane. Cluster upgrades are in `../../33-cluster-upgrade`.

# HPA vs Karpenter

- HPA helps to `Scale Pod`. Karpenter helps to `Scale Node`

- HPA triggered by Pod metrics such as: CPU, memory, or custom metrics. Karpenter is triggered by pending scheduling Pod

- HPA is part of Kubernetes distribution. Karpenter needs to be installed
