# 32.02 — EKS Auto Mode vs self-managed Karpenter

## 🎯 Scenario
Auto Mode **runs Karpenter for you**, so the scheduling brain is the same. The difference is who owns the controller, the AMI, the add-ons and the node access. This demo creates the same kind of NodePool on both and compares what you can and cannot change.

## 🗺 Architecture
```
Self-managed:  you ─► Helm chart + IAM + SQS + CloudFormation ─► Karpenter in YOUR nodes ─► EC2NodeClass ─► your AMI choice
Auto Mode:     AWS ─► managed Karpenter outside your nodes   ─► NodePool + NodeClass (eks.amazonaws.com) ─► AWS-managed AMI
```

## Comparison
| Dimension | Self-managed Karpenter (`22-karpenter`) | EKS Auto Mode (`32-auto-mode`) |
|-----------|------------------------------------------|---------------------------------|
| Scheduler / consolidation engine | Karpenter 1.15.x | Karpenter-based, version owned by AWS |
| Who upgrades the controller | You (Helm, compatibility matrix) | AWS (see `33-cluster-upgrade` for the upgrade runbook) |
| Where the controller runs | Pods on a node group you operate | Managed by AWS, no controller pods in your cluster |
| NodeClass API | `karpenter.k8s.aws/v1` `EC2NodeClass` | `eks.amazonaws.com/v1` `NodeClass` |
| Instance labels | `karpenter.k8s.aws/instance-*` | `eks.amazonaws.com/instance-*` |
| AMI | `amiSelectorTerms`: AL2023, Bottlerocket, custom AMI, pin or `@latest` | AWS-managed immutable AMI, no choice |
| Node access | SSH / SSM if you enable it | None (no SSH, no SSM). Use DaemonSets and `kubectl debug` |
| `userData` / kubelet tuning | Yes | Limited to NodeClass fields |
| Node max lifetime | You set `expireAfter` (default 720h) | Default 336h, hard maximum 21 days |
| Windows nodes | Possible with extra setup | Not supported (Linux only) |
| VPC CNI, CoreDNS, kube-proxy, LB controller, EBS CSI, Pod Identity agent | You install and upgrade | Built in |
| Built-in default pools | None, you write them | `general-purpose`, `system` (enable or disable only) |
| Extra cost | None | Management fee per instance-hour on top of EC2 ([pricing](https://aws.amazon.com/eks/pricing/)) |
| Mixed with other compute | Yes | Yes, Auto Mode nodes can run next to managed node groups |

### Scenarios
| Scenario | Pick | Why |
|----------|------|-----|
| Small platform team, many clusters, no wish to patch nodes | **Auto Mode** | AWS owns node patching, controller upgrades and add-ons |
| Need a custom AMI, Bottlerocket tuning, `userData`, kernel modules or SSH for audits | **Karpenter** | Auto Mode locks the node |
| Regulated workload that must control the exact AMI release and patch window | **Karpenter** | Pinned `al2023@v...` alias plus your own promotion process |
| Cost-sensitive fleet that runs mostly Spot and Savings Plans | **Karpenter** (compare) | Auto Mode fee is not reduced by Spot or Savings Plans, so test the numbers |
| Startup that wants production-ready defaults quickly | **Auto Mode** | One flag at cluster creation |
| Windows or unsupported instance types | **Karpenter** | Auto Mode is Linux only and supports a defined instance set |
| Existing Karpenter cluster, happy with it | **Stay** | Migration is possible but is its own project |

## ✅ Prerequisites
- `32-auto-mode/01-auto-mode` cluster running (Auto Mode).
- Optional for the live side by side: a second cluster from `22-karpenter` (`MODE=standard` + install).

## 🚀 Steps
### 1. Create a custom NodePool on Auto Mode (Spot + Graviton)
```bash
kubectl apply -f manifests/nodepool-spot-arm.yaml
# spot-arm appears next to the two built-in pools
kubectl get nodepools      

kubectl get deployment

kubectl scale deployment batch --replicas 3
kubectl scale deployment batch --replicas 0
kubectl get nodeclaims -o wide -w                      # one arm64 Spot node, labelled workload=batch
kubectl get nodes -L workload,kubernetes.io/arch,karpenter.sh/capacity-type
```

### 2. Read the difference in the YAML
Compare with `../../22-karpenter/02-implement/manifests/nodepool.yaml`:
```bash
diff <(sed -n '/nodeClassRef/,/name:/p' ../../22-karpenter/02-implement/manifests/nodepool.yaml) \
     <(sed -n '/nodeClassRef/,/name:/p' manifests/nodepool-spot-arm.yaml)
```
Only three things change: `nodeClassRef` (`group`, `kind`), the label prefix (`eks.amazonaws.com/`), and no `kubernetes.io/os` requirement.


### 3. Record what you observed
| Metric | Karpenter | Auto Mode |
|--------|-----------|-----------|
| Pods to install before first workload | controller (2) + IAM + SQS | 0 |
| Time from `scale` to Running pod | | |
| Who patched the node AMI last | you | AWS |
| Can you pin an AMI release | yes | no |

## 🔍 Validation
- `spot-arm` pool is `Ready` and its node has `karpenter.sh/capacity-type=spot` and `kubernetes.io/arch=arm64`.
- `kubectl get nodeclaims` shows the claim referencing `NodeClass/default` (Auto Mode) rather than an `EC2NodeClass`.

## 🧹 Cleanup
```bash
kubectl delete deployment batch
kubectl delete nodepool spot-arm
```

## 📝 Notes & cost
- Use **separate clusters** for the two models in this demo. Both reconcile `karpenter.sh/v1` NodePools, so mixing
  them in one cluster needs a deliberate migration. See the
  [EKS migration guide](https://docs.aws.amazon.com/eks/latest/userguide/migrate-auto.html) when you move.
- Custom Auto Mode `NodeClass` objects need their own node role and an access entry of type `EC2`
  (see [Create a Node Class](https://docs.aws.amazon.com/eks/latest/userguide/create-node-class.html)).
- ⚠️ **Not tested against a live AWS account.** The NodePool validates against the Karpenter 1.15.3 CRD schema.
  Auto Mode's own CRD may add rules that only a live cluster shows.
