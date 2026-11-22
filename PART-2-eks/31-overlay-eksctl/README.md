# 31 — More pods per node and fewer VPC IPs, built with eksctl

## 🎯 Scenario
This is the eksctl version of [`30-no-vpc-ip-pods`](../30-no-vpc-ip-pods/README.md). The demos are the same, but `eksctl` replaces Terraform so that one command builds a cluster and one command deletes it, with no state file to keep.

The default AWS VPC CNI gives every pod an IP from a VPC subnet. Two problems follow: subnets run out of IPs, and the instance's ENI/IP limit caps pods per node (`24-max-pod`: t3.medium = 17 pods). This folder walks the **native AWS options first**, then shows where a third-party CNI becomes the answer.

| Sub-demo | Approach | Pod IPs come from | Max pods on t3.medium |
|---|---|---|---|
| `24-max-pod` (baseline) | default VPC CNI | main subnets | 17 |
| [`02-secondary-cidr`](02-secondary-cidr/README.md) | **native:** VPC CNI custom networking, then + prefix delegation | secondary VPC CIDR `100.64.0.0/16` | 12, then 110 with prefix delegation |
| [`01-cilium-overlay`](01-cilium-overlay/README.md) | **third-party:** Cilium overlay (VXLAN) replaces the VPC CNI | private pool `192.168.0.0/16`, **no VPC IPs** | 110 (kubelet `maxPods`) |

Both demos use a **new cluster on EKS Kubernetes 1.37**, an **eksctl-managed `/24` VPC** (`10.100.0.0/24`, the smallest eksctl allows) split into `/27` subnets of 27 usable IPs each, **public node IPs** and **no NAT gateway**, and finish with an ALB in front of ~100 pods of `vietaws/eks:v1`.

## 🧭 Native first, third-party second
The ENI limit per instance type is fixed by EC2; no setting raises it. What you can change is how many pod IPs each ENI slot yields, and where those IPs come from. Try the options in this order:

| Step | Native option | Fixes | Limit you hit next |
|---|---|---|---|
| 1 | Larger instance type, or more nodes | pod density | cost; the ENI limit grows with instance size |
| 2 | Prefix delegation (`ENABLE_PREFIX_DELEGATION`) + kubelet `maxPods` | pod density (17 → 110 on t3.medium) | each prefix needs a contiguous `/28` free in the subnet; use **new** node groups when switching ([prefixes](https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html)) |
| 3 | Custom networking (secondary CIDR) | main subnets running out of IPs | lowers pods per node (12 on t3.medium) until combined with step 2; pods still use VPC IPs; the CIDR must be unique for peering ([custom networking](https://docs.aws.amazon.com/eks/latest/userguide/cni-custom-network.html)) |
| 4 | IPv6 cluster | IP exhaustion (AWS's first recommendation) | clients and dependencies must handle IPv6; cannot combine with custom networking ([IP optimization](https://docs.aws.amazon.com/eks/latest/best-practices/ip-opt.html)). Not covered here |
| 5 | Steps 2 + 3 together | density **and** main-subnet exhaustion | needs a secondary CIDR no peer uses — see `02-secondary-cidr` |

Managed node groups without a custom AMI also cap `maxPods` at **110** for instances under 30 vCPUs and **250** above that, whatever the CNI ([how maxPods is determined](https://docs.aws.amazon.com/eks/latest/userguide/choosing-instance-type.html#max-pods-precedence)).

**When a third-party CNI (Cilium, Calico) is justified:**

| Situation | Why native is not enough |
|---|---|
| You cannot get a pod range that is unique across all peered VPCs, Transit Gateway and on-premises | any VPC CIDR (primary or secondary) that overlaps blocks peering; an overlay keeps pods out of the VPC address space |
| You need eBPF datapath features, L7 policy or flow observability beyond the VPC CNI network policy | not provided by the VPC CNI |

**What the third-party route costs:** AWS supports only the VPC CNI on EC2 nodes ([alternate CNIs](https://docs.aws.amazon.com/eks/latest/userguide/alternate-cni-plugins.html)); pods are not routable from the VPC, so ALB/NLB targets must be `instance`; webhooks called by the API server need `hostNetwork`; EKS Auto Mode is not supported; you own CNI upgrades.

### Comparison
| | Cilium overlay | VPC CNI + secondary CIDR (+ prefix delegation) |
|---|---|---|
| Uses VPC subnet IPs for pods | No | Yes, from the secondary CIDR (main subnets spared) |
| VPC peering with a peer that uses the pod range | Works (pod range is not a VPC CIDR) | **Blocked** by AWS |
| Pods per node (t3.medium) | 110 | 12 → 110 with prefix delegation |
| Datapath | VXLAN encapsulation | native VPC routing |
| Pods routable from the VPC | No (SNAT to node IP) | Yes |
| ALB target type | `instance` only | `ip` or `instance` |
| API-server-to-pod webhooks | need `hostNetwork` | work normally |
| Support | partner / commercial / you | AWS |

### Scenarios
| Scenario | Pick |
|---|---|
| Subnets nearly full, least change, AWS support required | Secondary CIDR (add prefix delegation for density) |
| Only pod density is the problem, subnets have room | Prefix delegation alone (no secondary CIDR) |
| Very high density, pods never reached from the VPC, ranges overlap with peers | Cilium overlay |
| Other VPC workloads call pods directly, or ALB/NLB `ip` targets are required | Secondary CIDR |
| New cluster and IPv6 is possible | IPv6 cluster (not covered here) |

### Performance past the default pod limit
These are qualitative, **not benchmarks**. Once IPs stop being the limit, these become the limit:
- **CPU and memory:** usually hit first. A t3.medium (2 vCPU, 4 GiB) only fits 100 pods because the demo pods are idle with tiny requests.
- **Instance network bandwidth:** shared by every pod on the node.
- **kubelet and container runtime:** more pods per node means more probes, restarts and startup work per node.
- **EC2 API calls:** without prefixes the VPC CNI makes more ENI/IP calls, which slows pod launches at scale; AWS states prefixes give the best launch time ([prefixes](https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html)).
- **Overlay:** VXLAN adds encapsulation overhead and lowers the effective MTU.

## ✅ Prerequisites
- An AWS CLI profile, region `ap-southeast-1`. Every script takes the profile as an optional argument; without it the default AWS profile is used (`AWS_PROFILE` if set, otherwise `[default]`). Scripts print the account ID before doing anything.
- `eksctl` (latest 0.232.0; must accept Kubernetes `1.37`; `./scripts/render.sh && eksctl create cluster -f .rendered/cluster.yaml --dry-run` tells you), `kubectl`, `helm`, `jq`, `aws`, `python3`.
- Read [`24-max-pod`](../24-max-pod/README.MD) for the ENI formula.
- A deliberately small main VPC: `10.100.0.0/24` gives two public `/27` subnets (27 usable IPs each) for nodes and the ALB. This is close to real environments where the routable range is scarce, and it makes IP exhaustion visible in stage 0 of `02-secondary-cidr`.
- Cluster names `vietvn-overlay-ctl` and `vietvn-secondary-ctl` differ from the Terraform demos, so both can exist side by side.
- **Configuration:** each sub-demo has one `config.env` with every name, CIDR, size and version. The `*.yaml` files are templates rendered into `.rendered/` by the scripts, so a value is changed in one place. Shared script helpers live in `lib/common.sh`.

## 🚀 Steps
Run the demos **one at a time** and delete each cluster before starting the next. The native demo first:
1. [`02-secondary-cidr`](02-secondary-cidr/README.md): `./scripts/up.sh [profile]`, then `./scripts/stage.sh 1 [profile]` and `./scripts/stage.sh 2 [profile]`
2. [`01-cilium-overlay`](01-cilium-overlay/README.md): `./scripts/up.sh [profile]`

## 🔍 Validation
Each sub-demo compares `AvailableIpAddressCount` of the subnets before and after scaling to 100 pods, lists pods per node, and tests pod-to-pod, pod-to-internet and ALB access.

## 🧹 Cleanup
`./scripts/down.sh [profile]` in each sub-demo (use the same profile as `up.sh`): it deletes the ALB first (its ENIs and security groups are not created by eksctl and would block the VPC deletion), then runs `eksctl delete cluster --wait`.

## 📝 Notes & cost
- **Not tested against a live AWS account.** eksctl dry runs, `shellcheck`, Helm rendering and offline script tests pass. Points that need a real run are listed in each sub-demo.
- Cilium 1.20.5 is not e2e-tested by the Cilium project on Kubernetes 1.37 (its docs list up to 1.36). See the compatibility table in `01-cilium-overlay`.
- Demo-grade security: public subnets, public node IPs, open egress. Do not use this layout in production.
- You pay hourly for the EKS control plane, 2 EC2 instances and an ALB ([EKS](https://aws.amazon.com/eks/pricing/), [EC2](https://aws.amazon.com/ec2/pricing/on-demand/), [ELB](https://aws.amazon.com/elasticloadbalancing/pricing/)). There is no NAT gateway.
