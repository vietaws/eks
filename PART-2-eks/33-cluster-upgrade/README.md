# 33 — EKS cluster upgrade runbook (managed node group, Karpenter, Auto Mode)

## 🎯 Scenario
A customer asks: *"We are behind on Kubernetes versions. How do we upgrade, will there be downtime, and what
changes with Karpenter or Auto Mode?"* This demo upgrades **three clusters in parallel, 1.36 → 1.37**, with the
same app, the same load balancer type and the same probe, and records failed requests, time, manual steps and cost.

> ✅ Targets **EKS 1.37**, Karpenter **1.15.3**, AWS Load Balancer Controller **3.6.3**, nodes `t9g.small`
> (Graviton5, arm64). This is the only upgrade demo: `22-karpenter` and `32-auto-mode` link here instead of repeating it.

> 💸 **Three control planes, three NAT gateways, three NLBs and nine small nodes bill together.** Run `./scripts/down-all.sh`
> the same day. Use `./scripts/cost.sh` to see the burn rate while the clusters run.

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
| `upg-mng`  | Managed node group, 3 × `t9g.small` | You (`eksctl upgrade nodegroup`) | `MODE=standard` |
| `upg-karp` | 2 × `t9g.small` managed node group (hosts Karpenter) + Karpenter pool `upgrade-demo` (pinned AMI) | Karpenter drift (workload nodes), you (the node group) | `MODE=standard` + `22-karpenter/scripts/install-karpenter.sh` |
| `upg-auto` | EKS Auto Mode, custom pool `upgrade-demo` pinned to `t9g.small` | Auto Mode, after the control plane upgrade | `MODE=auto` |

Every cluster runs `manifests/app.yaml` (3 replicas on separate nodes, readiness probe, `preStop` sleep, PDB
`maxUnavailable: 1`) behind an **IP-target NLB**: the AWS Load Balancer Controller on `upg-mng` and `upg-karp`,
the built-in controller on `upg-auto`. Same load balancer type everywhere, so the failed-request counts compare.

```
        ┌──────────── probe.sh (laptop) ───────────┐    ┌── watch-upgrade.sh (laptop) ──┐
        ▼                                          │    ▼                               │
   NLB (ip targets) ─► web ×3 on 3 nodes     endpoints ready, nodes by version, PDB allowed
```

## ✅ Prerequisites
- `eksctl` ≥ 0.230.0, `kubectl`, `aws` CLI (profile `eks`), `helm`, `jq`, `envsubst` (`brew install gettext`), `curl`.
  Optional: `hey` (`brew install hey`) for `load.sh`.
- `t9g.small` must be offered in the region. Check:
  `aws ec2 describe-instance-type-offerings --region ap-southeast-1 --filters Name=instance-type,Values=t9g.small`
- **Fallback:** if Auto Mode does not launch `t9g.small`, delete the clusters and re-create all three with
  `NODE_TYPE=t4g.small` so the comparison stays fair.
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
source scripts/env.sh karp      # mng | karp | auto : sets CLUSTER_NAME and a private KUBECONFIG
./scripts/deploy-app.sh         # prints the URL
```
Terminal roles: **T1** commands, **T2** `./scripts/probe.sh <url> 0.2 1`, **T3** `./scripts/watch-upgrade.sh`,
optional **T4** `./scripts/load.sh <url> 30m 50`.

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
**`upg-mng` (you roll the nodes)**
```bash
eksctl upgrade nodegroup --name "${CLUSTER_NAME}-ng" --cluster "$CLUSTER_NAME" --kubernetes-version "$NEW_VERSION"
```
The group updates one node at a time (`maxUnavailable: 1`), cordoning and draining each old node behind the PDB.

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
Then the node group that hosts Karpenter (Karpenter cannot roll the nodes it runs on):
```bash
eksctl upgrade nodegroup --name "${CLUSTER_NAME}-ng" --cluster "$CLUSTER_NAME" --kubernetes-version "$NEW_VERSION"
```

**`upg-auto` (nothing to run)**
Auto Mode starts replacing nodes after the control plane upgrade, observing PDBs and the pool budget (`nodes: "1"`).
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
eksctl upgrade nodegroup --name "${CLUSTER_NAME}-ng" --cluster "$CLUSTER_NAME" --kubernetes-version "$OLD_VERSION"
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
- `t9g.small` has 2 vCPU and 2 GiB. The Karpenter controller requests 1 vCPU and 1 GiB per replica on `upg-karp`:
  it fits but leaves little room. Use `NODE_TYPE=t4g.medium` for the cluster if scheduling fails.
- ⚠ **Not tested against a live AWS account.** `probe.sh` was exercised against a local HTTP server (outage and
  recovery). All scripts pass `bash -n` and `shellcheck`. The `jq` filters in `watch-upgrade.sh` and `preflight.sh`
  were run on sample JSON. `cost.sh` price lookups and the Auto Mode `t9g.small` pool are unverified: report differences.
