# upg-auto step by step

`upg-auto` is an EKS Auto Mode cluster. There is no node group, no custom AMI and no controller to upgrade:

| Nodes | Runs | How they move to 1.37 |
|-------|------|-----------------------|
| Custom pool `upgrade-demo` (3 x `t4g.medium`) | The `web` app | Auto Mode replaces them after the control plane upgrade, observing PDBs and the pool budget (`nodes: "1"`) |
| Built-in pools `system`, `general-purpose` | Whatever AWS or your pods need (often 0 nodes) | Auto Mode, same way |

You run **one** upgrade command (the control plane), plus updates for any EKS add-on you installed yourself.
Everything else is watching.
Source: [Update the Kubernetes version of an EKS Auto Mode cluster](https://docs.aws.amazon.com/eks/latest/userguide/auto-upgrade.html).

Open 3 tabs in `33-cluster-upgrade` and run `source scripts/env.sh auto` in each one.

## T2 & T3
T2 (probe) and T3 (watcher), start these first and leave them running.

```bash
# T2
LB=$(kubectl get svc web -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
./scripts/probe.sh "http://$LB" 0.2 1

# T3
./scripts/watch-upgrade.sh
```
On this cluster `nodeclaims` in T3 counts the Auto Mode nodes (3 at the start).

## T1 (commands)

0. Check the starting state:

```bash
# upgrade-demo: 3 nodes
kubectl get nodepools


# 3 pods, one per node, READINESS GATES 1/1
kubectl get nodes -o custom-columns=NAME:.metadata.name,VER:.status.nodeInfo.kubeletVersion,POOL:.metadata.labels.karpenter\\.sh/nodepool,OS:.status.nodeInfo.osImage
kubectl get pods -l app=web -o wide


kubectl get ns default --show-labels
# eks.amazonaws.com/pod-readiness-gate-inject=enabled
```
Node names are EC2 instance IDs (`i-...`) and the OS is Bottlerocket (EKS Auto). There is no SSH or SSM on these nodes.

1. Baseline: wait about 2 minutes. T2 should show 0 failures.
   The bad/good drain test (`upg-mng.md` steps 2-3) is optional here. If you run it, note that with the bad app (1 replica) Auto Mode consolidates the empty nodes after 5 minutes, so switching back to good waits for new nodes.

2. Preflight: `./scripts/preflight.sh 1.37`.

Exit 1 means fix the blockers first. A PDB with `maxUnavailable: 0` matters most here: Auto Mode observes PDBs, so it would hold the node replacement until the pool's `terminationGracePeriod` (1h) forces it.

3. Control plane (about 10 min). This is the only upgrade command on this cluster:

```bash
eksctl upgrade cluster --name "$CLUSTER_NAME" --version "$NEW_VERSION" --approve
```

T3 should show `cp=1.37/ACTIVE` while the nodes are on 1.36, and T2 should show 0 failures.

4. Data plane: nothing to run. Watch Auto Mode replace the nodes:

```bash
# new claim -> Ready -> old claim deleted, one at a time
kubectl get nodeclaims -w

# VERSION goes from v1.36 to v1.37
kubectl get nodes -L karpenter.sh/nodepool -w   

# why and when a node is replaced              
kubectl get events -w | grep -i -E 'drift|disrupt|evict'      
```

Expected: the pool budget (`nodes: "1"`) replaces one node at a time. Each new node comes up **before** the old one is drained, the PDB keeps at least 2 web pods ready, and the readiness gate keeps a new pod out of service until its
NLB target is Healthy. T2 stays at 0 failures. T3 shows `nodeclaims` go 3 -> 4 -> 3 three times.

Auto Mode chooses its own timing, so this can take longer than `upg-mng` or `upg-karp`. To finish the demo sooner, let it replace up to 3 nodes at once (the PDB still allows only 1 web pod down at a time):

```bash
kubectl patch nodepool upgrade-demo --type merge -p '{"spec":{"disruption":{"budgets":[{"nodes":"3"}]}}}'
# back to the default afterwards
kubectl patch nodepool upgrade-demo --type merge -p '{"spec":{"disruption":{"budgets":[{"nodes":"1"}]}}}'
```

Do not delete nodes or node claims by hand: that skips the mechanism you are testing.

5. Add-ons and controllers: skip. VPC CNI, CoreDNS, kube-proxy, load balancing, EBS CSI and Karpenter are part of Auto Mode. You still own your apps, self-managed add-ons and any EKS add-on you installed yourself:

```bash
eksctl get addon --cluster "$CLUSTER_NAME"                    # metrics-server is an EKS add-on: you update it
eksctl update addon --cluster "$CLUSTER_NAME" --name metrics-server --version latest --wait
```

6. Optional PDB stall test, during step 4:

```bash
kubectl patch pdb web --type merge -p '{"spec":{"maxUnavailable":0}}'
kubectl get nodeclaims -w                    # the old node is not drained: Auto Mode waits on the PDB
kubectl get events -w | grep -i -E 'evict|disrupt'
kubectl patch pdb web --type merge -p '{"spec":{"maxUnavailable":1}}'
```

The pool sets `terminationGracePeriod: 1h`, so a node blocked by a PDB is forced out after one hour at the latest.

7. Record the results. In T2, press Ctrl-C. Note the failed count, the longest outage, the total time from step 3 until the last node is on 1.37, and how many manual commands you ran (one upgrade command plus the add-on you installed yourself, compare with `upg-mng` and `upg-karp`).

You can delete `upg-auto` as soon as you finish it. `down.sh` deletes the Service first (Auto Mode removes the NLB), then the `upgrade-demo` pool and its nodes, then the cluster:

```bash
KUBECONFIG=$HOME/.kube/upg-auto.config ../02-create-eks-cluster/scripts/down.sh --cluster-name=upg-auto --region=ap-southeast-1
```

No load balancer controller IAM policy was created for this cluster, so there is nothing to delete in IAM.
