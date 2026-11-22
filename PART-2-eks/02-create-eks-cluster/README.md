# 02 — Shared demo cluster (up / down scripts)

## 🎯 Scenario
One pair of scripts creates and deletes the cluster that the later demos reuse, so
`22-karpenter` and `32-auto-mode` do not repeat cluster-creation steps.

| `MODE` | Config | What you get | Used by |
|--------|--------|--------------|---------|
| `standard` (default) | `cluster.yaml` | EKS cluster, IAM OIDC provider, Pod Identity agent add-on, **one public managed node group** (2 × t9g.medium, AL2023) | `22-karpenter`, `33-cluster-upgrade` |
| `auto` | `cluster-auto.yaml` | EKS cluster with **EKS Auto Mode**, IAM OIDC provider, built-in `system` + `general-purpose` NodePools, **no node group** | `32-auto-mode` |

> ℹ️ `MODE=auto` creates no node group on purpose. eksctl rejects node groups at creation when Auto Mode
> is enabled, and Auto Mode launches its own EC2 nodes (into the private subnets, through the one NAT gateway).

## ✅ Prerequisites
- AWS CLI with a profile that can create VPC, EKS, IAM, CloudFormation and EC2 resources.
- `eksctl` ≥ 0.230.0 (the Karpenter v1.15 guide requires it), `kubectl`, `jq`. Upgrade with `brew upgrade eksctl`.
- EKS 1.37 is available in standard support (see the [version calendar](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html)).

## 🚀 Steps
```bash
cd 02-create-eks-cluster

# Plain cluster for Karpenter (about 15-20 min)
./scripts/up.sh --mode=standard --cluster-name=eksdemo

# or EKS Auto Mode
./scripts/up.sh --mode=auto --cluster-name=eksauto

# an older version, for the upgrade demo (33-cluster-upgrade)
./scripts/up.sh --version=1.36 --mode=standard --cluster-name=eksdemo
```

| Option | Default | Meaning |
|--------|---------|---------|
| `--mode` | `standard` | `standard` or `auto` |
| `--cluster-name` | `eksdemo` | Also the `karpenter.sh/discovery` tag value |
| `--version` | `1.37` | Kubernetes minor version |
| `--region` | `ap-southeast-1` | Region |
| `--node-type` | `t9g.medium` | `--mode=standard` only: managed node group instance type |
| `--node-count` | `2` | `--mode=standard` only: managed node group size (`--node-max` defaults to count + 2) |

Options also accept the `--option value` form and fall back to the matching environment variable (`MODE`, `CLUSTER_NAME`, ...). Without `--profile` the scripts use the default AWS credentials. Run `./scripts/up.sh --help` for the full list.

## 🔍 Validation
```bash
kubectl get nodes -o wide                 # standard: 2 public nodes. auto: none yet
kubectl get nodepools                     # auto: system, general-purpose
eksctl get cluster --name eksdemo
```

## 🧹 Cleanup
```bash
./scripts/down.sh                         # prompts for cluster name [eksdemo] and region [ap-southeast-1], then asks for 'yes'
./scripts/down.sh --cluster-name=eksauto --region=ap-southeast-1 --force   # no prompts
```
`down.sh` deletes, in order: Ingresses and LoadBalancer Services, workloads and PVCs, custom
NodePools (and waits for their nodes), the Karpenter Helm release, launch templates and the
`Karpenter-<cluster>` CloudFormation stack, then the cluster. It finishes with a leftover check.

## 📝 Notes & cost
- ⚠️ **Not tested against a live AWS account.** The rendered configs validate against `eksctl utils schema`, and
  both scripts pass `shellcheck` and input-validation tests. Report any behavior that differs from this README.
- Cost while running: EKS control plane + 2 × t9g.medium + 1 NAT gateway. Check
  [EKS pricing](https://aws.amazon.com/eks/pricing/). Delete the cluster when you finish.
- The older manual walk-through is kept in `01-create-eks-cluster.md` and `00-cluster.yaml`.
