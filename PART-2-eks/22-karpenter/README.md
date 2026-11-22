# 22 — Karpenter Node Autoscaling

## 🎯 Scenario
Replace node group + Cluster Autoscaler with **Karpenter**: a just-in-time node provisioner that talks to the
EC2 API directly, picks the cheapest instance that fits the pending pods, and consolidates to save cost.

> ✅ Targets **Karpenter 1.15.x** (stable `karpenter.sh/v1` API) on **EKS 1.37**, with the **AL2023** AMI family and **EKS Pod Identity**. 1.15.x supports Kubernetes 1.36 and 1.37 (see the
> [compatibility matrix](https://karpenter.sh/docs/upgrading/compatibility/)).

Latest Karpenter Release: https://github.com/aws/karpenter-provider-aws/releases

## 🗺️ Sub-demos
| Step | Folder | Teaches |
|------|--------|---------|
| 1 | `01-configure` | Intro, components, Spot handling, install (CloudFormation + Pod Identity + Helm) |
| 2 | `02-implement` | EC2NodeClass + NodePool, first nodes |
| 3 | `03-consolidation` | Bin-pack and remove under-used nodes to cut cost |
| 4 | `04-drift` | Replace nodes when the NodePool, EC2NodeClass or AMI changes |
| 5 | `05-expired` | Node expiry (`expireAfter`) for freshness |
| 6 | `06-spot-availability` | Spot cost report, zero-downtime proof with a probe, simulated Spot interruption |

## 🔁 Demo flow
```
01-configure ──► 02-implement ──► 03-consolidation ──► 04-drift ──► 05-expired ──► 06-spot-availability
 install         scale UP          scale DOWN           REPLACE     REPLACE        PROVE cost and uptime
 Karpenter       (pending pods     (repack, delete      (spec/AMI   (max node      (Spot price, PDB, probe,
                  → new nodes)      cheaper)             changed)    age)           interruption)
```
Focus: **scaling and replacing nodes**. The EKS control plane upgrade is a separate demo (`../33-cluster-upgrade`).

| Phase | What you do | What you should see | Conclusion |
|-------|-------------|---------------------|------------|
| 01 | `up.sh --mode=standard`, `install-karpenter.sh` | Karpenter pods Running, CRDs present | Karpenter is a Deployment plus AWS roles, queue and rules. You own its upgrades |
| 02 | Apply EC2NodeClass + NodePool, scale `inflate` to 5 | NodeClaims and Spot nodes appear in about a minute | Pending pods alone trigger right-sized nodes, no node group |
| 03 | Scale `inflate` 8 → 2 | Node count drops, pods repacked | Scale-down is automatic, policy decides how aggressive |
| 04 | Change the NodePool or AMI alias | Old nodes tainted, replacements first | Drift patches nodes safely, PDBs and budgets set the pace |
| 05 | Set `expireAfter` to 15m | Nodes recycled on schedule | Max node age is a hygiene safety net |
| 06 | Deploy `web` + prober, run cost report, trigger drift, interrupt a Spot node | Large saving, `FAIL` count 0 when protected, failures when not | Cost comes from Spot + flexibility, uptime comes from the workload settings |

## ✅ Prerequisites
- `eksctl` ≥ 0.230.0, `kubectl`, `helm`, `aws` CLI, `envsubst` (`brew install gettext`); optional `eks-node-viewer`.
- The shared cluster from `02-create-eks-cluster` (`--mode=standard`): OIDC, Pod Identity agent, a public node
  group and `karpenter.sh/discovery` tags are already set up there.

## 🚀 Steps
```bash
(cd ../02-create-eks-cluster && ./scripts/up.sh --mode=standard --cluster-name=eksdemo --region=ap-southeast-1)   # about 15-20 min
./scripts/install-karpenter.sh --cluster-name=eksdemo --region=ap-southeast-1                                      # Karpenter 1.15.3
export CLUSTER_NAME=eksdemo AWS_REGION=ap-southeast-1                                                              # used by envsubst in the next demos
```
Use the same `--cluster-name` and `--region` for both scripts. Without flags both default to `eksdemo` and `ap-southeast-1`.
Then follow `02-implement` → `03-consolidation` → `04-drift` → `05-expired` → `06-spot-availability`. Upgrading a cluster that runs Karpenter is
covered once, for all compute types, in `../33-cluster-upgrade`.

## 🔍 Validation
```bash
kubectl get nodepool,ec2nodeclass,nodeclaims
kubectl logs -f -n kube-system -l app.kubernetes.io/name=karpenter -c controller
```

## 🧹 Cleanup
```bash
(cd ../02-create-eks-cluster && ./scripts/down.sh --cluster-name=eksdemo)
```
`down.sh` removes the NodePools and their nodes, the Helm release, launch templates and the `Karpenter-<cluster>` CloudFormation stack before it deletes the cluster.

## 📝 Notes & cost
- **Why Karpenter over Cluster Autoscaler:** no ASG round trip, no per-variant node groups, native bin-packing, built-in Spot handling, consolidation.
- Biggest cost levers: allow **Spot + on-demand**, allow **amd64 + arm64** (Graviton), and use
  `consolidationPolicy: WhenEmptyOrUnderutilized` (or `Balanced`).
- Karpenter is **self-managed**: you upgrade it, keep it compatible with your Kubernetes version, and run it on nodes that it does not manage. `../32-auto-mode` shows the AWS-managed alternative.