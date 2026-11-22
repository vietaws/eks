# 22.04 — Karpenter Drift

## 🎯 Scenario
**Drift** replaces running nodes when they no longer match their NodePool or EC2NodeClass. You change
the spec, Karpenter marks the nodes `Drifted`, launches replacements, and drains the old ones.

## 🗺 Architecture
```
Edit NodePool / EC2NodeClass ──► Karpenter hashes the spec ──► NodeClaims marked Drifted
                              ──► replacement launched ──► old node tainted, drained, terminated
                                  (rate limited by disruption.budgets and PDBs)
```

## What counts as drift
| Changed object | Field examples | Triggers drift |
|----------------|----------------|----------------|
| NodePool | `requirements` (instance types, zone, arch), `labels`, `taints` | yes |
| NodePool | `limits`, `disruption`, `weight` | no (behavior fields) |
| EC2NodeClass | `amiSelectorTerms`, subnets, security groups, `role`, `tags`, block devices | yes |
| AMI | `al2023@latest` resolves to a new AMI (for example after the control plane upgrade) | yes |

Full list: https://karpenter.sh/docs/concepts/disruption/#drift. Drift is on by default in v1; there is
no feature gate to enable.

## ✅ Prerequisites
- Karpenter, `default` EC2NodeClass and NodePool from `../02-implement`.

## 🚀 Steps
### Part 1: requirement drift (instance category `m` → `c`)
```bash
kubectl apply -f manifests/app.yaml
kubectl scale deployment inflate --replicas 2

# 1. Restrict the pool to the m family and let the pods land on it
kubectl patch nodepool default --type json -p '[
  {"op":"replace","path":"/spec/template/spec/requirements/3/values","value":["m"]}]'
kubectl get nodes -L node.kubernetes.io/instance-type -w

# 2. Change the allowed category to c: existing m nodes no longer match
kubectl patch nodepool default --type json -p '[
  {"op":"replace","path":"/spec/template/spec/requirements/3/values","value":["c"]}]'
kubectl get nodeclaims -w
kubectl logs -f -n kube-system -l app.kubernetes.io/name=karpenter -c controller | grep -i drift
```
> Index `3` is the `karpenter.k8s.aws/instance-category` requirement in `../02-implement/manifests/nodepool.yaml`.
> Check with `kubectl get nodepool default -o jsonpath='{.spec.template.spec.requirements}'` if you changed the file.

### Part 2: AMI drift (data plane patching)
`amiSelectorTerms` controls the AMI:

| `alias` | Behavior |
|---------|----------|
| `al2023@latest` | Always the newest recommended AMI. A new AMI release, or a Kubernetes control plane upgrade, drifts the nodes automatically. Convenient for dev. |
| `al2023@v20260101` (pinned release) | Nodes stay on that AMI until **you** change the alias. You control when the roll happens. Recommended for production and tested in lower environments first. |

```bash
# Find the release string of the current recommended AMI
K8S_VERSION=$(kubectl version -o json | jq -r '"\(.serverVersion.major).\(.serverVersion.minor)"' | tr -d '+')
aws ssm get-parameter \
  --name "/aws/service/eks/optimized-ami/${K8S_VERSION}/amazon-linux-2023/x86_64/standard/recommended/image_id" \
  --query Parameter.Value --output text |
  xargs aws ec2 describe-images --query 'Images[0].Name' --image-ids
# the name ends with the release, for example ...-v20260115 -> alias al2023@v20260115

# Pin, then later move to latest to trigger drift
export CLUSTER_NAME=eksdemo AMI_ALIAS="al2023@v20260115"   # use the value found above
envsubst < ../02-implement/manifests/ec2nodeclass.yaml | kubectl apply -f -
export AMI_ALIAS="al2023@latest"
envsubst < ../02-implement/manifests/ec2nodeclass.yaml | kubectl apply -f -
```
The drift check runs about every 5 minutes, but editing the NodePool or EC2NodeClass triggers it immediately.
A cluster upgrade triggers the same mechanism. A pinned alias is resolved per Kubernetes version, so after a control
plane upgrade you move the alias to a release that exists for the new version. That runbook is in `../../33-cluster-upgrade`.

### Control the blast radius
```yaml
spec:
  disruption:
    budgets:
      - nodes: "20%"
        reasons: ["Drifted"]
      - nodes: "0"                      # no drift replacement during working hours
        schedule: "0 9 * * mon-fri"     # UTC cron
        duration: 8h
        reasons: ["Drifted"]
```

## 🔍 Validation
```bash
kubectl get nodeclaims -o custom-columns=NAME:.metadata.name,DRIFTED:.status.conditions[?(@.type==\"Drifted\")].status
kubectl get nodes -L node.kubernetes.io/instance-type
```
Expected: old nodes get the `karpenter.sh/disrupted:NoSchedule` taint, replacements appear first, then
the old nodes disappear. The `inflate` pods are rescheduled, so a service needs at least 2 replicas and a PDB
to avoid downtime.

## 🧹 Cleanup
```bash
kubectl delete deployment inflate
```

## 📝 Notes
- Drift is **voluntary** disruption, so it respects PDBs and `karpenter.sh/do-not-disrupt`.
- Changing `expireAfter` on the NodePool drifts existing nodes too (their NodeClaims keep the old value).
- Spot interruptions and instance health events are **involuntary** and ignore budgets.
