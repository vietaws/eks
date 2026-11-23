# upg-karp step by step

`upg-karp` has two kinds of nodes, and you upgrade them in two different ways:

| Nodes | Runs | How they move to 1.37 |
|-------|------|-----------------------|
| Managed node group `upg-karp-ng` (2 nodes) | Karpenter, LB controller, CoreDNS, metrics-server | You: node group blue/green (custom AMI, no in-place upgrade) |
| Karpenter pool `upgrade-demo` (3 nodes) | The `web` app | Karpenter drift, after you move the pinned AMI alias |

Open 3 tabs in `33-cluster-upgrade` and run `source scripts/env.sh karp` in each one.

## T2 & T3
T2 (probe) and T3 (watcher), start these first and leave them running.

```bash
# T2
LB=$(kubectl get svc web -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
./scripts/probe.sh "http://$LB" 0.2 1

# T3
./scripts/watch-upgrade.sh
```
On this cluster `nodeclaims` in T3 counts the Karpenter nodes (3 at the start).

## T1 (commands)

0. Pin the node type to what the pool runs today. `env.sh` defaults to `t9g.medium`, and re-applying `karpenter.yaml` with a different type would also change the node size during the drift:

```bash
export NODE_TYPE=$(kubectl get nodepool upgrade-demo \
  -o jsonpath='{.spec.template.spec.requirements[?(@.key=="node.kubernetes.io/instance-type")].values[0]}')
echo "$NODE_TYPE"                                   # t9g.small on the current cluster
kubectl get ec2nodeclass default -o jsonpath='{.spec.amiSelectorTerms}{"\n"}'   # the pinned alias, e.g. al2023@v20261119
```

1. Baseline: wait about 2 minutes. T2 should show 0 failures.
   The bad/good drain test (`upg-mng.md` steps 2-3) is optional here. If you run it, note that with the bad app (1 replica) Karpenter consolidates the empty nodes after 5 minutes, so switching back to good waits for new nodes.

2. Preflight: `./scripts/preflight.sh 1.37`.

Exit 1 means fix the blockers first. Also check that the Karpenter version supports 1.37 (1.15.x covers 1.36 and 1.37, see the Karpenter compatibility matrix).

3. Control plane (about 10 min):

```bash
eksctl upgrade cluster --name "$CLUSTER_NAME" --version "$NEW_VERSION" --approve
```

T3 should show `cp=1.37/ACTIVE` while the nodes are on 1.36, and T2 should show 0 failures.

4. Check the EC2NodeClass right after the control plane upgrade. Karpenter resolves the pinned alias for the cluster's **current** version. If the same release exists for 1.37, Karpenter finds new AMIs and starts drifting nodes by itself. If it does not exist, the class has no AMI and Karpenter cannot launch any node until you do step 5:

```bash
kubectl get ec2nodeclass default -o jsonpath='{.status.amis}' | jq          # empty = no AMI for 1.37 with this alias
kubectl get ec2nodeclass default -o jsonpath='{range .status.conditions[*]}{.type}={.status} {end}{"\n"}'

kubectl get nodeclaims
```

5. Workload nodes: promote the AMI alias to a 1.37 release (Karpenter drift, one node at a time):

```bash
./scripts/ami-release.sh 1.37 list | tail -5

# releases that exist for 1.37

export AMI_ALIAS="$(./scripts/ami-release.sh 1.37 latest)"; echo "$AMI_ALIAS"
envsubst '${CLUSTER_NAME} ${AMI_ALIAS} ${NODE_TYPE}' < manifests/karpenter.yaml | kubectl apply -f -
kubectl get ec2nodeclass default -o jsonpath='{.status.amis}' | jq

# now 1.37 AMIs
kubectl get nodeclaims  -w # Drifted -> new claim -> old node gone
```

Expected: the pool budget (`nodes: "1"`) replaces one node at a time. Each new node comes up **before** the old one is drained, the PDB keeps at least 2 web pods ready, and the readiness gate keeps a new pod out of service until its NLB target is Healthy. T3 shows `nodeclaims` go 3 -> 4 -> 3 three times.
Wait until no claim shows `Drifted` before step 6, so the two rollouts do not overlap.

6. Node group that hosts Karpenter: blue/green (Karpenter cannot roll the nodes it runs on, and
   `eksctl upgrade nodegroup --kubernetes-version` fails on a custom AMI):

```bash
# Same type and size as the current group
NG_OLD="$(eksctl get nodegroup --cluster "$CLUSTER_NAME" --region "$AWS_REGION" -o json | jq -r '.[0].Name')"

read -r NG_TYPE NG_SIZE < <(eksctl get nodegroup --cluster "$CLUSTER_NAME" --region "$AWS_REGION" --name "$NG_OLD" -o json \
  | jq -r '.[0] | "\(.InstanceType) \(.DesiredCapacity)"')

NG_NEW="${CLUSTER_NAME}-ng-${NEW_VERSION//./}"     # upg-karp-ng-137


AMI="$(aws ssm get-parameter --region "$AWS_REGION" \
  --name "/aws/service/eks/optimized-ami/${NEW_VERSION}/amazon-linux-2023/arm64/standard/recommended/image_id" \
  --query Parameter.Value --output text)"

echo "$NG_OLD -> $NG_NEW: ${NG_SIZE} x ${NG_TYPE}, AMI $AMI"   # upg-karp-ng -> upg-karp-ng-137: 2 x t9g.small

# Green: the new group joins next to the old one
cat <<EOF | eksctl create nodegroup -f -
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata: {name: ${CLUSTER_NAME}, region: ${AWS_REGION}, version: "${NEW_VERSION}"}
managedNodeGroups:
  - name: ${NG_NEW}
    instanceType: ${NG_TYPE}
    amiFamily: AmazonLinux2023
    ami: ${AMI}
    desiredCapacity: ${NG_SIZE}
    minSize: ${NG_SIZE}
    maxSize: $((NG_SIZE + 2))
    volumeSize: 20
    privateNetworking: false
EOF
kubectl get nodes -L eks.amazonaws.com/nodegroup,karpenter.sh/nodepool    # 2 old + 2 new group nodes, 3 pool nodes

# Blue out: cordon + drain the old group behind the PDBs, then delete it
eksctl delete nodegroup --cluster "$CLUSTER_NAME" --region "$AWS_REGION" --name "$NG_OLD"

# Karpenter and the LB controller now run on the new group
kubectl -n kube-system get pods -l app.kubernetes.io/name=karpenter -o wide
kubectl -n kube-system get pods -l app.kubernetes.io/name=aws-load-balancer-controller -o wide
```

Expected: T2 stays at 0 failures. The web pods are on the Karpenter nodes and do not move. Karpenter runs 1 replica,
so while its pod moves (under a minute) Karpenter cannot launch nodes. The running nodes are not affected.

7. Add-ons and controllers:

```bash
for a in vpc-cni coredns kube-proxy eks-pod-identity-agent; do eksctl update addon --cluster "$CLUSTER_NAME" --name "$a" --version latest --wait; done
./scripts/install-lbc.sh
kubectl -n kube-system get deploy karpenter -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'   # still a 1.37-compatible version
```

8. Optional PDB stall test, during step 5 (Karpenter drift):

```bash
kubectl patch pdb web --type merge -p '{"spec":{"maxUnavailable":0}}'
kubectl get nodeclaims -w                    # the Drifted node is not drained: Karpenter waits on the PDB
kubectl get events -w | grep -i -E 'evict|disrupt'
kubectl patch pdb web --type merge -p '{"spec":{"maxUnavailable":1}}'
```

The pool sets `terminationGracePeriod: 1h`, so a node blocked by a PDB is forced out after one hour at the latest.

9. Record the results. In T2, press Ctrl-C. Note the failed count, the longest outage, the total time from step 3 to step 7, and how many manual commands you ran (compare with `upg-mng`: here you also promoted the AMI alias and replaced the system node group).

You can delete `upg-karp` as soon as you finish it. `down.sh` also removes the Karpenter pools, nodes, launch templates and the `Karpenter-upg-karp` CloudFormation stack:

```bash
KUBECONFIG=$HOME/.kube/upg-karp.config ../02-create-eks-cluster/scripts/down.sh --cluster-name=upg-karp --region=ap-southeast-1
aws iam delete-policy --policy-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/AWSLoadBalancerControllerIAMPolicy-upg-karp"
```

Do that only if you don't need it for side-by-side comparison. Then continue with `upg-auto`.
