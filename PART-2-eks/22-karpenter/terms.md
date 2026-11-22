# Karpenter terms

Short definitions for the words used in this demo. Terms are grouped by topic, each with the demo that uses it.

## Core objects

| Term | Meaning | Demo |
|------|---------|------|
| **Karpenter** | Node autoscaler that watches pending pods and launches EC2 instances directly through the EC2 API, with no Auto Scaling Group. It also removes, repacks and replaces nodes. | all |
| **NodePool** (`karpenter.sh/v1`) | Rules for the nodes Karpenter may create: allowed instance categories, sizes, architectures, zones, capacity types (Spot or On-Demand), taints, labels, a `limits` cap, and the disruption settings. One cluster can have many NodePools. | `02-implement` |
| **EC2NodeClass** (`karpenter.k8s.aws/v1`) | The AWS side of a node: AMI (`amiSelectorTerms`), subnets, security groups, node IAM role, block devices, user data, tags. Many NodePools can point to one EC2NodeClass through `nodeClassRef`. | `02-implement` |
| **NodeClaim** | The request for one node, created by Karpenter from a NodePool. It tracks the node from launch to deletion and carries conditions such as `Launched`, `Registered`, `Drifted`, `Expired`. You read it, you do not create it. | `02-implement` |
| **Node** | The Kubernetes Node object that appears when the EC2 instance of a NodeClaim joins the cluster. | all |
| **`nodeClassRef`** | Field in a NodePool that names its EC2NodeClass (`group`, `kind`, `name`). | `01-configure` |
| **AMI alias** | Value such as `al2023@latest` or `al2023@v20260115` in `amiSelectorTerms`. `latest` follows the newest EKS-optimized AMI. A pinned release stays until you change it. | `04-drift` |
| **KarpenterNodeRole** | IAM role created by the CloudFormation stack and attached to Karpenter-launched nodes. It must be mapped into the cluster (access entry or `iamidentitymapping`) so nodes can join. | `01-configure` |
| **Interruption queue** | SQS queue fed by EventBridge rules. Karpenter reads it to learn about Spot interruptions and health events. It is turned on with the Helm value `settings.interruptionQueue`. | `01-configure` |

## How nodes are created

| Term | Meaning |
|------|---------|
| **Pending (unschedulable) pod** | A pod the Kubernetes scheduler could not place. This is Karpenter's trigger. |
| **Batching** | Karpenter waits a short window (about 1 s idle, up to 10 s) so several pending pods are handled in one decision. |
| **Bin packing** | Fitting pods onto as few and as cheap instances as possible, using their resource requests. |
| **Requirements** | Constraints in a NodePool, written as `key operator values`, for example `karpenter.sh/capacity-type In [spot, on-demand]`. |
| **Capacity type** | `spot` or `on-demand` (label `karpenter.sh/capacity-type`). Karpenter prefers Spot when both are allowed. |
| **Instance flexibility** | Allowing many instance types, sizes and architectures so Karpenter can pick the cheapest one that has capacity. More flexibility gives lower cost and fewer launch failures. |
| **`limits`** | Maximum total resources (for example `cpu: 100`) a NodePool may create. It protects the account from runaway scaling. |
| **`weight`** | Priority between NodePools. A higher weight is tried first. |
| **Taints / `startupTaints`** | Taints placed on new nodes so only matching pods land there. |
| **Graviton** | AWS Arm (`arm64`) instances. Usually cheaper per unit of work. Images must support `arm64`. |

## Spot

| Term | Meaning |
|------|---------|
| **Spot instance** | Spare EC2 capacity at a large discount that EC2 can reclaim with a 2-minute warning. |
| **Spot interruption** | EC2 reclaiming a Spot instance. It is **involuntary** disruption: PDBs and budgets do not apply. |
| **Rebalance recommendation** | Early signal that a Spot instance is at higher risk of interruption. |
| **price-capacity-optimized** | EC2 Fleet allocation strategy that Karpenter uses for Spot. It balances low price with deep capacity pools, so the very cheapest but fragile pool is avoided. |
| **Spot-to-Spot consolidation** | Replacing one Spot node with a cheaper Spot node. Off by default (feature gate `SpotToSpotConsolidation`) and needs at least 15 candidate instance types. Deleting an under-used Spot node works without it. |

## Disruption (nodes leaving)

| Term | Meaning |
|------|---------|
| **Disruption** | Any removal or replacement of a node by Karpenter. It is either *voluntary* (consolidation, drift, expiration) or *involuntary* (Spot interruption, health events). |
| **Voluntary disruption** | Planned by Karpenter. It respects PDBs, `do-not-disrupt` and disruption budgets. |
| **Involuntary disruption** | Forced by AWS (Spot reclaim, instance failure). It ignores PDBs and budgets. |
| **Consolidation** | Removing empty nodes and repacking or replacing under-used nodes to cut cost. Policy `consolidationPolicy`: `WhenEmpty`, `WhenEmptyOrUnderutilized`, `Balanced`. |
| **`consolidateAfter`** | How long a node must stay empty or under-used before Karpenter acts. `Never` turns consolidation off. |
| **Drift** | A running node no longer matches its NodePool or EC2NodeClass, for example a changed requirement, label, subnet, or a new AMI. Karpenter replaces it. |
| **Expiration (`expireAfter`)** | Maximum node lifetime (Karpenter default `720h`, 30 days; the demo NodePool uses `336h`, 14 days). After it, the node is replaced even if nothing else changed. `Never` disables it. |
| **`terminationGracePeriod`** | On a NodePool, the longest time a node may spend draining. After it, remaining pods are force-deleted, even if a PDB or `do-not-disrupt` would block them. |
| **Disruption budget** (`disruption.budgets`) | Limit on how many nodes of a NodePool may be disrupted at once, as a number or percent, optionally per reason (`Drifted`, `Underutilized`, `Empty`) and per cron schedule. `nodes: "0"` freezes voluntary disruption. |
| **Disrupted taint** | `karpenter.sh/disrupted:NoSchedule`, added to a node about to be drained so no new pods land on it. |
| **Replacement first** | Karpenter launches the replacement node before it drains the old one, when the pods need new capacity. |
| **Drain** | Evicting the pods of a node, respecting PDBs, before the instance is terminated. |

## Protecting workloads

| Term | Meaning |
|------|---------|
| **PDB (PodDisruptionBudget)** | Kubernetes object that limits how many pods of an app can be evicted at once (`minAvailable` or `maxUnavailable`). Honored by voluntary disruption. A PDB with `maxUnavailable: 0` blocks draining. |
| **`karpenter.sh/do-not-disrupt: "true"`** | Annotation on a pod or node that blocks voluntary disruption of that node. |
| **Readiness probe** | Check that keeps traffic away from pods that are not ready, including freshly rescheduled ones. |
| **`preStop` hook** | Command that runs before a container stops, for example `sleep 10`, so in-flight requests finish. |
| **Topology spread constraint** | Pod setting that spreads replicas across zones or nodes, so losing one node does not remove the whole service. |
| **Replicas** | At least 2 are needed for zero downtime during node replacement. |

## Related Kubernetes and AWS terms

| Term | Meaning |
|------|---------|
| **HPA** | Horizontal Pod Autoscaler: changes the number of pods. Karpenter changes the number of nodes. |
| **Cluster Autoscaler** | Older node autoscaler that resizes Auto Scaling Groups. Slower and needs one node group per node variant. |
| **EKS Auto Mode** | AWS-managed compute that runs a Karpenter-based node provisioner for you. See `../32-auto-mode`. |
| **EKS Pod Identity** | Way to give a pod an IAM role. The Karpenter controller uses it through a Pod Identity association. |
| **EventBridge / SQS** | AWS services that carry Spot and health events to Karpenter. |
| **AWS FIS** | Fault Injection Service. Used in `06-spot-availability` to send a real Spot interruption notice. |
| **`eks-node-viewer`** | Optional terminal tool that shows nodes, utilization and hourly cost. |

## Sources
- Concepts and disruption: https://karpenter.sh/docs/concepts/disruption/
- Compatibility matrix: https://karpenter.sh/docs/upgrading/compatibility/
- PodDisruptionBudget: https://kubernetes.io/docs/tasks/run-application/configure-pdb/
