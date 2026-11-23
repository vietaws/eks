# 33 — EKS cluster upgrade runbook (managed node group, Karpenter, Auto Mode)

## 🎯 Scenario
A customer asks: *"We are behind on Kubernetes versions. How do we upgrade, will there be downtime, and what changes with Karpenter or Auto Mode?"* This demo upgrades **three clusters in parallel, 1.36 → 1.37**, with the same app, the same load balancer type and the same probe, and records failed requests, time, manual steps and cost.


> 💸 **Three control planes, three NAT gateways, three NLBs and nine small nodes bill together.** Run `./scripts/down-all.sh` the same day. Use `./scripts/cost.sh` to see the burn rate while the clusters run.

## 🧭 Where this demo sits in the learning path
```
01-prep ─► 02-create-eks-cluster ─► … networking (03-16) … ─► 21-cluster-autoscaler
   ─► 22-karpenter (01–05: install, consolidation, drift, expiry)     self-managed node provisioning
   ─► 32-auto-mode (01–02: capabilities, vs Karpenter)                 managed node provisioning
   ─► 33-cluster-upgrade (this demo)                                   uses all three compute models
```
Do `22/04-drift` and `32/01` first: this demo assumes you have seen drift and an Auto Mode cluster.

## 🗺 Architecture
| Cluster | Compute | Who rolls the nodes | Created with |
|---------|---------|---------------------|--------------|
| `upg-mng`  | Managed node group, 3 × `t9g.medium` | You (node group blue/green: `eksctl create nodegroup` + `eksctl delete nodegroup`) | `MODE=standard` |
| `upg-karp` | 2 × `t9g.medium` managed node group (hosts Karpenter) + Karpenter pool `upgrade-demo` (pinned AMI) | Karpenter drift (workload nodes), you (the node group) | `MODE=standard` + `22-karpenter/scripts/install-karpenter.sh` |
| `upg-auto` | EKS Auto Mode, custom pool `upgrade-demo` pinned to `t4g.medium` (Auto Mode does not offer t9g or any small size) | Auto Mode, after the control plane upgrade | `MODE=auto` |

Every cluster runs `manifests/app.yaml` (3 replicas on separate nodes, readiness probe, `preStop` sleep, PDB `maxUnavailable: 1`) behind an **IP-target NLB**: the AWS Load Balancer Controller on `upg-mng` and `upg-karp`, the built-in controller on `upg-auto`. Same load balancer type everywhere, so the failed-request counts compare.

```
        ┌──────────── probe.sh (laptop) ───────────┐    ┌── watch-upgrade.sh (laptop) ──┐
        ▼                                          │    ▼                               │
   NLB (ip targets) ─► web ×3 on 3 nodes     endpoints ready, nodes by version, PDB allowed
```

## ✅ Prerequisites
- `eksctl` ≥ 0.230.0, `kubectl`, `aws` CLI (profile `eks`), `helm`, `jq`, `envsubst` (`brew install gettext`), `curl`.
  Optional: `hey` (`brew install hey`) for `load.sh`.

- Permissions: the account can create EKS, VPC, IAM, CloudFormation, SQS/EventBridge (Karpenter) resources.

## 🚀 Steps
### 0. Create the three clusters at 1.36 (about 25 minutes, in parallel)
```bash
cd 33-cluster-upgrade
./scripts/up-all.sh            # logs in ${TMPDIR:-/tmp}/upg-logs/
```
Open three terminals for the cluster you are testing and repeat for the other two (or run the clusters one after another). In each terminal:
```bash
cd 33-cluster-upgrade
source scripts/env.sh auto      # mng | karp | auto : sets CLUSTER_NAME and a private KUBECONFIG
./scripts/deploy-app.sh         # prints the URL

# Or run below command in each terminal to get URL
kubectl get svc web
```
Terminal roles: 

- **T1** above commands
- **T2** `./scripts/probe.sh <url> 0.2 1`
- **T3** `./scripts/watch-upgrade.sh`,
- Optional **T4** `./scripts/load.sh <url> 30m 50`.

### 1. Baseline and a deliberate failure (about 10 minutes, run on `upg-mng`)
Let the probe run for two minutes: it must show zero failures. Then show where downtime really comes from:
```bash
./scripts/deploy-app.sh bad                                   # 1 replica, no probe, no PDB
NODE=$(kubectl get pod -l app=web -o jsonpath='{.items[0].spec.nodeName}')
kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data
kubectl uncordon "$NODE"
./scripts/deploy-app.sh good                                  # same drain again, now with 3 replicas, PDB, preStop
NODE=$(kubectl get pod -l app=web -o jsonpath='{.items[0].spec.nodeName}'); kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data; kubectl uncordon "$NODE"
```
Expected: the bad app shows a run of failed probe requests while the pod restarts and the NLB re-registers it.
The hardened app shows none. A node drain is exactly what every upgrade does to your pods.
`deploy-app.sh` keeps the Service, so the NLB hostname and a running probe survive a switch between `bad` and `good`.
The switch itself rolls the pods and can cause a few failed requests: count only the failures during the drain.

**Bad app vs good app.** Same image, same Service and NLB. Only the deployment settings differ:

| Setting | Bad (`manifests/app-bad.yaml`) | Good (`manifests/app.yaml`) | What happens during a node drain without it |
|---------|-------------------------------|-----------------------------|---------------------------------------------|
| Replicas | 1 | 3, one per node (`topologySpreadConstraints` with `matchLabelKeys: [pod-template-hash]`) | The only pod is evicted, nothing serves traffic until the new pod is up |
| PodDisruptionBudget | none | `maxUnavailable: 1` | A drain may evict every replica at once |
| Readiness probe | none | yes | The NLB sends traffic to a pod that is not listening yet |
| NLB pod readiness gate | off (namespace label removed) | on: `deploy-app.sh` labels the namespace (`elbv2.k8s.aws/pod-readiness-gate-inject` on `upg-mng`/`upg-karp`, `eks.amazonaws.com/pod-readiness-gate-inject` on `upg-auto`) | A new pod is Ready before its NLB target is Healthy, so a rollout can leave only Initial/Draining targets |
| `preStop` sleep | none | 25s, longer than the NLB deregistration delay (20s) | The pod exits while the NLB still routes requests to it |
| `terminationGracePeriodSeconds` | 5 | 45 | In-flight requests are cut off |
| Rollout strategy | default (25% unavailable) | `maxUnavailable: 0`, `maxSurge: 1`, `minReadySeconds: 5` | A redeploy can drop capacity below what is needed |
| Expected probe result on drain | a run of failed requests | 0 failed requests | |

### 2. Preflight (every cluster)
```bash
./scripts/preflight.sh 1.37        # exit 1 = blockers (ERROR insights, zero-disruption PDBs, version skew)
```
Fix blockers first. Warnings (single replicas, fail-closed webhooks, missing probes) are risks you decide on.

### 3. Control plane, 1.36 → 1.37 (about 10 minutes, API stays up)
Start the probe and the watcher first, then:
```bash
eksctl upgrade cluster --name "$CLUSTER_NAME" --version "$NEW_VERSION" --approve
```
Expected: `watch-upgrade.sh` shows `cp=1.37/ACTIVE` while node versions are still 1.36. No failed probe requests:
EKS replaces the API servers behind the same endpoint and running pods are not touched.

### 4. Data plane, per compute type
> ⚠ **Managed node groups here use a custom AMI, so `eksctl upgrade nodegroup --kubernetes-version` fails** with
> `cannot specify kubernetes-version or release-version when using a custom AMI`. eksctl does not know `t9g`, so
> `../02-create-eks-cluster/scripts/up.sh` creates the group with the arm64 AL2023 AMI as `ami:`, and EKS cannot
> change the version of a custom-AMI group. Both `upg-mng` and `upg-karp` therefore upgrade their node group
> **blue/green**: create a new group on the new version, then delete the old one (eksctl drains it through the
> eviction API, so the PDB is respected). `upg-auto` has no node group and is not affected.

**Node group blue/green (used by `upg-mng` and `upg-karp`)**
```bash
# Same type and size as the current group. NG_OLD is "${CLUSTER_NAME}-ng" on the first upgrade.
NG_OLD="$(eksctl get nodegroup --cluster "$CLUSTER_NAME" --region "$AWS_REGION" -o json | jq -r '.[0].Name')"
read -r NG_TYPE NG_SIZE < <(eksctl get nodegroup --cluster "$CLUSTER_NAME" --region "$AWS_REGION" --name "$NG_OLD" -o json \
  | jq -r '.[0] | "\(.InstanceType) \(.DesiredCapacity)"')
NG_NEW="${CLUSTER_NAME}-ng-${NEW_VERSION//./}"                        # e.g. upg-mng-ng-137
AMI="$(aws ssm get-parameter --region "$AWS_REGION" \
  --name "/aws/service/eks/optimized-ami/${NEW_VERSION}/amazon-linux-2023/arm64/standard/recommended/image_id" \
  --query Parameter.Value --output text)"
echo "$NG_OLD -> $NG_NEW: ${NG_SIZE} x ${NG_TYPE}, AMI $AMI"

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
kubectl get nodes -L eks.amazonaws.com/nodegroup                     # old (1.36) and new (1.37) nodes, all Ready

# Blue out: cordon + drain every old node behind the PDB, then delete the group
eksctl delete nodegroup --cluster "$CLUSTER_NAME" --region "$AWS_REGION" --name "$NG_OLD"
```
The node group name changes to `$NG_NEW`. The commands above look it up again, so they also work for the rollback.

**`upg-mng` (you roll the nodes)**
Run the node group blue/green above. Expected: T3 shows nodes moving from 1.36 to 1.37 and the web pods moving to
the new group. The PDB keeps at least 2 pods ready and the readiness gate keeps each new pod out of service until
its NLB target is Healthy, so the probe stays at 0 failures.

**`upg-karp` (Karpenter drift, then the node group)**
The AMI alias is **pinned**. A pinned alias resolves per Kubernetes version, so after the control plane upgrade the
old release string may not exist for 1.37. Move the alias to a 1.37 release (this is the "promote" step you test in
non-prod first):
```bash
./scripts/ami-release.sh 1.37 list | tail -5               # releases that exist for 1.37
export AMI_ALIAS="$(./scripts/ami-release.sh 1.37 latest)"
envsubst '${CLUSTER_NAME} ${AMI_ALIAS} ${NODE_TYPE}' < manifests/karpenter.yaml | kubectl apply -f -
kubectl get ec2nodeclass default -o jsonpath='{.status.amis}' | jq     # now 1.37 AMIs
kubectl get nodeclaims -w                                              # Drifted → replacement → old node gone, one at a time
```
Then the node group that hosts Karpenter (Karpenter cannot roll the nodes it runs on): run the **node group
blue/green** above. Wait until `kubectl get nodeclaims` shows no `Drifted` claims first, so the two rollouts do not
overlap. The Karpenter controller pods are evicted to the new group behind their own PDB. While a controller pod
restarts, Karpenter cannot launch nodes, but the workload nodes keep running. Check after the swap:
```bash
kubectl -n kube-system get pods -l app.kubernetes.io/name=karpenter -o wide   # Running on the new group's nodes
```

**`upg-auto` (nothing to run)**
No managed node group and no custom AMI: Auto Mode picks the AMI for the new version itself, so the custom-AMI
limit above does not apply. Auto Mode starts replacing nodes after the control plane upgrade, observing PDBs and the pool budget (`nodes: "1"`).
Watch only:
```bash
kubectl get nodes -L eks.amazonaws.com/compute-type -w
kubectl get nodeclaims -w
```
Auto Mode chooses its own replacement timing, so this run can take the longest. To finish a demo sooner, raise
`budgets[].nodes` on the `upgrade-demo` pool (for example to `"3"`). Do not delete nodes by hand: that skips the
mechanism you are testing.

### 5. Add-ons and controllers
```bash
# upg-mng, upg-karp: EKS add-ons and the controller you installed
eksctl get addon --cluster "$CLUSTER_NAME"
for a in vpc-cni coredns kube-proxy eks-pod-identity-agent; do eksctl update addon --cluster "$CLUSTER_NAME" --name "$a" --version latest --wait; done
./scripts/install-lbc.sh                                   # re-run: upgrades the controller if you bump LBC_VERSION
# upg-karp only: check the Karpenter compatibility matrix before AND after (1.15.x covers 1.36 and 1.37)
```
`upg-auto`: skip. vpc-cni, CoreDNS, kube-proxy, load balancing, block storage and Karpenter are AWS's job. You still
own your own apps, self-managed add-ons and any EKS add-on you installed yourself.

### 6. A PDB that stalls the upgrade (any cluster, during step 4)
```bash
kubectl patch pdb web --type merge -p '{"spec":{"maxUnavailable":0}}'
kubectl get nodes -w                                        # versions stay mixed: the drain waits
kubectl get events -w | grep -i evict                       # "Cannot evict pod ... disruption budget"
./scripts/preflight.sh 1.37                                 # reports the zero-disruption PDB as a BLOCKER
kubectl patch pdb web --type merge -p '{"spec":{"maxUnavailable":1}}'
```
A zero-disruption PDB causes no downtime but blocks every node upgrade. The pools set `terminationGracePeriod: 1h`
so a stuck drain eventually proceeds.

### 7. Rollback (optional, within 7 days of the upgrade)
```bash
aws eks list-insights --cluster-name "$CLUSTER_NAME" --filter '{"categories":["ROLLBACK_READINESS"]}'
# upg-mng / upg-karp: nodes first (a node cannot be newer than the control plane)
#   node group: run the step 4 blue/green with NEW_VERSION="$OLD_VERSION" (custom AMI, no in-place downgrade)
#   upg-karp: also move AMI_ALIAS to a 1.36 release and re-apply manifests/karpenter.yaml
aws eks update-cluster-version --name "$CLUSTER_NAME" --kubernetes-version "$OLD_VERSION"
# upg-auto: the same update-cluster-version call; EKS drifts the Auto Mode nodes back first (default timeout 720 min)
```
Add-ons are not rolled back for you. See the [rollback guide](https://docs.aws.amazon.com/eks/latest/userguide/rollback-cluster.html)
and [Auto Mode rollback](https://docs.aws.amazon.com/eks/latest/userguide/rollback-automode.html).

## 🔍 Validation — did the service go down?
Four independent views. All four must agree.

| Layer | Tool | Detects | Pass |
|-------|------|---------|------|
| Client | `probe.sh` (CSV per request, 1 s timeout) | Any non-200 or slow request, longest outage | Failed < 0.1%, longest outage 0 s |
| Load | `load.sh` (`hey`, 50 req/s) | Errors and p99 latency under real traffic | Only `[200]` in the status distribution |
| Cluster | `watch-upgrade.sh` (CSV every 5 s) | Ready endpoints, pending pods, nodes by version, PDB allowance | Endpoints never below 2 (no `!!`), pending pods clear within 30 s |
| AWS | CloudWatch NLB metrics `HealthyHostCount`, `UnHealthyHostCount`, `TargetResponseTime` for the NLB of each cluster | Targets leaving and joining, deregistration | `HealthyHostCount` never 0 |

Scaling during the upgrade: `watch-upgrade.sh` records `nodeclaims` and `nodes` next to `pending`. A healthy run
shows the replacement node arriving **before** the old one leaves. Optional: run `load.sh` at a higher rate during
step 4 and watch whether Karpenter or Auto Mode adds nodes (more `nodeclaims`) while the old ones drain.

Final state:
```bash
kubectl get nodes -o wide                                   # all v1.37.x
kubectl get pods -A | grep -vE 'Running|Completed'          # nothing
aws eks list-insights --cluster-name "$CLUSTER_NAME" --filter '{"categories":["UPGRADE_READINESS"]}'
```

### Record your result
| | `upg-mng` | `upg-karp` | `upg-auto` |
|---|---|---|---|
| Failed / total requests (`probe.sh`) | | | |
| Longest outage | | | |
| p99 latency during the upgrade | | | |
| Wall-clock: control plane | | | |
| Wall-clock: nodes | | | |
| Commands you ran after the control plane | | | |
| Things you had to remember (add-ons, controller, AMI alias) | | | |
| EC2 cost / hour (`cost.sh`) | | | |
| Auto Mode fee / hour | n/a | n/a | |
| Total cost for the window (`./scripts/cost.sh <hours>`) | | | |

## 🧹 Cleanup
```bash
./scripts/down-all.sh            # type delete-all; deletes the three clusters in parallel
```
`eksctl` does not delete the IAM policies `AWSLoadBalancerControllerIAMPolicy-upg-*` created by `install-lbc.sh`. Delete them
if you do not need them.

## 📝 Notes & cost
- **Cost model:** each cluster pays the EKS control plane fee (standard support; the rate for an unsupported version
  is higher), EC2 nodes, a NAT gateway, an NLB, and on Auto Mode a management fee per instance-hour that does not shrink
  with Spot or Savings Plans. `cost.sh` reads prices from the Price List API, it does not hard-code them.
  Prices: [EKS](https://aws.amazon.com/eks/pricing/), [EC2](https://aws.amazon.com/ec2/pricing/on-demand/).
- **Fast answers for the customer**
  | Question | Answer |
  |----------|--------|
  | Downtime in the control plane upgrade? | None planned. The API stays reachable, clients reconnect. |
  | Where does downtime come from? | Node replacement: single replicas, no PDB, no readiness probe, no `preStop` delay, fail-closed webhooks. |
  | Skip versions? | No. One minor at a time. Kubelets may lag the API server by up to three minors. |
  | Undo? | Within 7 days, one minor back, for in-place upgrades. Nodes first (Auto Mode does it for you). |
  | Do nothing? | Standard support lasts 14 months, then paid extended support for 12 months, then an automatic upgrade. 1.36 standard support ends 2027-08-02. |
  | Who does what? | See the table in step 4 and 5. Auto Mode removes the node, add-on and controller steps, not your apps. |
- **In-place or blue/green?** In-place for routine one-minor steps with stateless apps. Blue/green when you are several
  minors behind, remove many APIs, or need an instant rollback. Cost: two clusters during the cutover.
- **Production habits shown here:** a pinned AMI alias promoted after testing, `terminationGracePeriod` on pools,
  pool budgets, preflight before every upgrade, one minor at a time, non-prod first. Keep the cluster definition in
  IaC and change the version there.
- `t9g.medium` has 2 vCPU and 4 GiB. The Karpenter controller requests 1 vCPU and 1 GiB per replica on `upg-karp`:
  it fits but leaves little room. Use a larger `NODE_TYPE` if scheduling fails.
- ⚠ **Not tested against a live AWS account.** `probe.sh` was exercised against a local HTTP server (outage and
  recovery). All scripts pass `bash -n` and `shellcheck`. The `jq` filters in `watch-upgrade.sh` and `preflight.sh`
  were run on sample JSON. `cost.sh` price lookups and the Auto Mode `t4g.medium` pool are unverified: report differences.
