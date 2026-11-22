# 22.02 — Implement Karpenter (NodePool + EC2NodeClass)

## 🎯 Scenario
Create a Karpenter **EC2NodeClass** and **NodePool**, then watch Karpenter launch right-sized nodes directly through the EC2 API when pods go pending.


## 🗺 Architecture
```
Pending pods → Karpenter → EC2 API → launch node (shape from NodePool, AWS settings from EC2NodeClass)
```

## ✅ Prerequisites
- Cluster from `02-create-eks-cluster` (`--mode=standard`) and Karpenter installed (`01-configure/04-install.md`).
- `envsubst` (`brew install gettext`) and `kubectl`.

## 🚀 Steps
```bash
export CLUSTER_NAME=vietvn2
export AMI_ALIAS="al2023@latest"      # newest EKS-optimized AL2023 AMI for the cluster's Kubernetes version

# 1. EC2NodeClass (AWS settings) and NodePool (what to launch)
envsubst < manifests/ec2nodeclass.yaml | kubectl apply -f -
kubectl apply -f manifests/nodepool.yaml

# 2. Wait until both are Ready
kubectl get ec2nodeclass,nodepool

# 3. Force node provisioning with a pending workload (1 vCPU per pod)
kubectl apply -f manifests/app.yaml

# Demo Scale-out: 0 -> 1 -> 8 -> 20
# Demo Scale-In: Scale 20 -> 8 -> 5 (Watch process scale down: kgp -w)

kubectl get pods -w

kubectl scale deployment inflate --replicas 0

kubectl scale deployment inflate --replicas 1

kubectl scale deployment inflate --replicas 3

kubectl scale deployment inflate --replicas 5

kubectl scale deployment inflate --replicas 8

kubectl scale deployment inflate --replicas 20
```

```bash
#Check SPOT to be Replaced by SPOT
kubectl get deploy karpenter -n kube-system \
-o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="FEATURE_GATES")].value}{"\n"}'

 helm get values karpenter -n kube-system | grep -i spotToSpot

 # Turn ON
 helm upgrade karpenter oci://public.ecr.aws/karpenter/karpenter --version 1.15.3 -n kube-system \
--reuse-values --set settings.featureGates.spotToSpotConsolidation=true

 # Turn OFF
 helm upgrade karpenter oci://public.ecr.aws/karpenter/karpenter --version 1.15.3 -n kube-system \
--reuse-values --set settings.featureGates.spotToSpotConsolidation=false

```

Notes
  - Restarts: either way, the Karpenter pods restart, because the value is a pod environment variable. Wait with `kubectl rollout status deployment/karpenter -n kube-system`.
  - Helm overwrite: a kubectl set env change is overwritten the next time you run helm upgrade or install-karpenter.sh, which sets the gate to true. Use Helm if you want the setting to stick.

## 🔍 Validation
```bash
kubectl get nodeclaims -o wide                       # one NodeClaim per node Karpenter launched
kubectl get nodes -L karpenter.sh/capacity-type,node.kubernetes.io/instance-type,kubernetes.io/arch
kubectl logs -f -n kube-system -l app.kubernetes.io/name=karpenter -c controller
```
Expected: within about a minute the `inflate` pods are Running on new Spot nodes that are **not** part of the managed node group, and the log shows `launched nodeclaim` / `registered nodeclaim`.

## 🧹 Cleanup
```bash
kubectl delete deployment inflate
kubectl delete nodepool default       # Karpenter drains and terminates its nodes
kubectl delete ec2nodeclass default
```

## ✅ Conclusion
- Pending pods are enough to make Karpenter create nodes: no node group to resize and no Auto Scaling Group.
- The NodePool states what is allowed (arch, Spot or On-Demand, instance category, limits). The EC2NodeClass states how it is built on AWS (AMI, subnets, security groups, role). Karpenter picks the cheapest shape that fits.
- Deleting the pods lets Karpenter remove the nodes again. To scale back, follow `../03-consolidation`.
- To prove cost and uptime with a real app, continue with `../06-spot-availability`.

## 📝 Notes & cost
- Allowing both `amd64` + `arm64` and `spot` + `on-demand` lets Karpenter pick the cheapest instance that fits. That is the core cost lever.
- `limits.cpu: 100` caps the pool. Remove or raise it only on purpose.
- Karpenter is **self-managed**: you own its upgrades and its IAM. `32-auto-mode` shows the managed alternative.
