# upg-mng step by step
  
Open 3 tabs in `33-cluster-upgrade` and run `source scripts/env.sh mng` in each one.


## T2 & T3
T2 (probe) and T3 (watcher), start these first and leave them running
  

```bash
## T2
LB=$(kubectl get svc web -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
./scripts/probe.sh "http://$LB" 0.2 1

# T3
./scripts/watch-upgrade.sh
```
  
## T1 (commands)
  
1. Baseline: wait about 2 minutes. T2 should show 0 failures.
2. Bad app drain. `deploy-app.sh` keeps the Service, so the NLB hostname and the running probe survive the switch. The switch itself rolls the pods and can cause a few failures: count only the failures during the drain.

```bash
./scripts/deploy-app.sh bad
NODE=$(kubectl get pod -l app=web -o jsonpath='{.items[0].spec.nodeName}')
kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data
kubectl uncordon "$NODE"
```

Expect a run of failures in T2 during the drain.

3. Good app drain:

```bash
./scripts/deploy-app.sh good
NODE=$(kubectl get pod -l app=web -o jsonpath='{.items[0].spec.nodeName}')
kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data
kubectl uncordon "$NODE"
```

Expect 0 failures.

4. Restart the probe so the upgrade numbers are clean. In T2, press Ctrl-C, note the summary, and start the probe again.
5. Preflight: `./scripts/preflight.sh 1.37`. 

Exit 1 means fix the blockers first.

6. Control plane (about 10 min):

```bash
eksctl upgrade cluster --name "$CLUSTER_NAME" --version "$NEW_VERSION" --approve
```

T3 should show cp=1.37/ACTIVE while the nodes are on 1.36, and T2 should show 0 failures.

7. Node group: blue/green (new 1.37 group, then drain and delete the old one).

`eksctl upgrade nodegroup --kubernetes-version` does **not** work here. It fails with
`cannot specify kubernetes-version or release-version when using a custom AMI`: eksctl does not know `t9g`, so `up.sh` created the group with a custom arm64 AMI (`ami:`), and EKS cannot change the version of a custom-AMI group. Replace the group instead:

```bash
# 7a. Confirm the control plane is on 1.37 first (T3 shows cp=1.37/ACTIVE)
aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --query 'cluster.[version,status]' --output text

# 7b. arm64 AL2023 AMI for 1.37
AMI=$(aws ssm get-parameter --region "$AWS_REGION" \
  --name /aws/service/eks/optimized-ami/${NEW_VERSION}/amazon-linux-2023/arm64/standard/recommended/image_id \
  --query Parameter.Value --output text); echo "$AMI"

# 7c. Green group: same size and type as the old one (the live nodes are t9g.small)
cat <<EOF | eksctl create nodegroup -f -
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata: {name: ${CLUSTER_NAME}, region: ${AWS_REGION}, version: "${NEW_VERSION}"}
managedNodeGroups:
  - name: ${CLUSTER_NAME}-ng-137
    instanceType: t9g.small
    amiFamily: AmazonLinux2023
    ami: ${AMI}
    desiredCapacity: 3
    minSize: 3
    maxSize: 5
    volumeSize: 20
    privateNetworking: false
EOF
kubectl get nodes -L eks.amazonaws.com/nodegroup     # 3 x 1.36 (old) + 3 x 1.37 (new), all Ready

# 7d. Blue group out: eksctl cordons and drains every old node through the eviction API (the PDB is respected)

```


T3 shows nodes moving from 1.36 to 1.37 and pods moving to the new group. The PDB keeps at least 2 pods ready and the readiness gate keeps each new pod out of service until its NLB target is Healthy, so T2 should stay at 0 failures.

Note: the group name changes to `${CLUSTER_NAME}-ng-137`. Use that name in any later `eksctl` command.

8. Add-ons:

```bash
for a in vpc-cni coredns kube-proxy eks-pod-identity-agent; do eksctl update addon --cluster "$CLUSTER_NAME" --name "$a" --version latest --wait; done
./scripts/install-lbc.sh
```

9. Optional PDB stall test: run README section 6 during step 7, or on its own after the upgrade.
10. Record the results. In T2, press Ctrl-C. Note the failed count, the longest outage, the total time from step 6 to step 8, and how many manual commands you ran.

You can delete upg-mng as soon as you finish it: 

```bash
eksctl delete cluster --name upg-mng --region ap-southeast-1


eksctl delete nodegroup --cluster "$CLUSTER_NAME" --name "${CLUSTER_NAME}-ng" --region "$AWS_REGION"


source scripts/env.sh mng
../02-create-eks-cluster/scripts/down.sh --cluster-name=upg-mng --region=ap-southeast-1   # type "yes" to confirm

export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws iam delete-policy --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy-upg-mng
```

Do that only if you don't need it for side-by-side comparison. After upg-mng, continue with upg-karp, then upg-auto.