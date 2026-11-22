# 31 / 02 — VPC CNI custom networking (secondary CIDR) + prefix delegation, with eksctl

## 🎯 Scenario
Same demo as [`30-no-vpc-ip-pods/02-secondary-cidr`](../../30-no-vpc-ip-pods/02-secondary-cidr/README.md), built with **eksctl**. Keep the AWS VPC CNI (fully AWS-supported) but move pod IPs out of your main subnets into a **secondary VPC CIDR** (`100.64.0.0/16`). Pods stay VPC-routable, so ALB `ip` targets and webhooks work unchanged.

Custom networking alone **lowers** pods per node (the primary ENI no longer serves pods). To go above the default limit you also enable **prefix delegation**. One cluster goes through three stages, each with its own node group:

| Stage | Setting | Node group | Pod IPs come from | t3.medium max pods |
|---|---|---|---|---|
| 0 | default VPC CNI (same as `24-max-pod`) | `ng-s0` | primary subnets `10.100.x.x` | 17 = 3×(6−1)+2 |
| 1 | + custom networking | `ng-s1` | secondary subnets `100.64.x.x` | 12 = (3−1)×(6−1)+2 |
| 2 | + prefix delegation, `maxPods=110` | `ng-s2` | `/28` prefixes of the secondary subnets | 110 |

Honest framing: pods still consume **VPC IPs**, but from the secondary CIDR. Your main (routable, scarce) subnets are spared.

## 🗺 Architecture
```
VPC 10.100.0.0/24 + secondary 100.64.0.0/16 (eksctl-managed, NO NAT gateway)
 ├─ public  10.100.0.0/27   (AZ a)  node 1 primary ENI, ALB, stage-0 pods  ┐ ENIConfig "ap-southeast-1a"
 ├─ public  10.100.0.32/27  (AZ b)  node 2 primary ENI, ALB, stage-0 pods  ┘ ENIConfig "ap-southeast-1b"
 ├─ private 10.100.0.64/27, 10.100.0.96/27  (eksctl, no NAT, no nodes; control-plane ENIs may sit here)
 ├─ pods    100.64.0.0/20   (AZ a)  pod ENIs of node 1 (scripts/secondary-cidr.sh, no internet route)
 └─ pods    100.64.16.0/20  (AZ b)  pod ENIs of node 2
ALB (internet-facing, target-type ip) ──► pod IP (100.64.x.x)

EKS cluster  vietvn-secondary-ctl  (Kubernetes 1.37, EKS add-ons vpc-cni / kube-proxy / coredns / pod-identity-agent)
```

| File | Purpose |
|---|---|
| `config.env` | **All values** (names, CIDRs, sizes, versions). Edit this file only |
| `cluster.yaml` | `/24` VPC (eksctl splits it into `/27`s), control plane, Pod Identity for the controller |
| `nodegroup-s0.yaml`, `-s1.yaml`, `-s2.yaml` | One node group per stage (`maxPodsPerNode`: default, 12, 110) |
| `addons-s1.yaml`, `addons-s2.yaml` | vpc-cni settings for each stage (`eksctl update addon`) |
| `manifests/` | Controller Helm values, app, IngressClass, ALB Ingress |
| `scripts/preflight-cidr.sh` | Fails if the planned CIDRs overlap any VPC in the account and region |
| `scripts/secondary-cidr.sh` | Associates `SECONDARY_CIDR` with the VPC and creates the two pod subnets, or removes both (eksctl does neither) |
| `scripts/render.sh` | Render the templates into `.rendered/` without AWS calls |
| `scripts/up.sh`, `stage.sh`, `down.sh`, `eniconfig.sh` | Build stage 0 (re-runnable, finished steps are skipped), move to stage 1 or 2, delete everything, create ENIConfigs |

## ⚠️ VPC peering warning
AWS **refuses to create a VPC peering connection if any CIDR of the two VPCs overlaps**, "even if you intend to use only the non-overlapping CIDR blocks" ([VPC peering limitations](https://docs.aws.amazon.com/vpc/latest/peering/vpc-peering-basics.html)). The secondary CIDR counts. If a peer VPC uses `100.64.0.0/16` (or any range inside it), peering fails and routing around it is not possible.

- `scripts/preflight-cidr.sh` runs before the cluster is created and exits non-zero on overlap with any VPC CIDR in this account and region. It cannot see other accounts, other regions or on-premises ranges, so check those yourself. `ALLOW_OVERLAP=1` turns the failure into a warning.
- When peering works (no overlap), pod traffic to the peer VPC is SNAT'd to the node's primary IP by the VPC CNI default (`AWS_VPC_K8S_CNI_EXTERNALSNAT=false`), so the peer sees addresses from `10.100.0.0/24`. **This SNAT behavior is not tested in this demo**; verify it with a pod-to-peer test before relying on it.
- If you cannot get unique ranges, the [Cilium overlay](../01-cilium-overlay/README.md) keeps pod IPs out of the VPC entirely, at the cost of AWS support and `ip` targets.

## ⚙️ Configuration
All names, CIDRs, sizes and versions live in **`config.env`** (cluster name, region, Kubernetes version, AZs, VPC/secondary/pod-subnet/service CIDRs, node group size and `maxPods` per stage, controller role name, Ingress/ALB names, chart version). Change a value there only.

The `*.yaml` files are **templates** with `${VAR}` placeholders. Every script first renders them into `.rendered/` (git-ignored) from `config.env`, and fails if a placeholder has no value. `up.sh` also checks the CIDRs: the pod subnets must sit inside `SECONDARY_CIDR`, and the VPC, secondary and service CIDRs must not overlap. Run `./scripts/render.sh` to render without touching AWS. Shared helpers are in `../lib/common.sh`.

## ✅ Prerequisites
- An AWS CLI profile, region `ap-southeast-1`. `up.sh`, `stage.sh` and `down.sh` take the profile as an optional last argument; without it the default AWS profile is used (`AWS_PROFILE` if set, otherwise `[default]`). Use the same profile for every step.
- `eksctl`, `kubectl`, `helm`, `jq`, `aws`, `python3` (used by the pre-flight script).
- Read [`24-max-pod`](../../24-max-pod/README.MD) first (stage 0 repeats it).

### Version compatibility (checked November 2026)
| Component | Version used | Status |
|---|---|---|
| EKS Kubernetes | `1.37` | Available, standard support until 2027-12-01 ([EKS versions](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html)) |
| Node AMI | AL2023 | Default for managed node groups on 1.30+ |
| AWS Load Balancer Controller chart | `3.6.3` | Current chart ([eks-charts](https://github.com/aws/eks-charts/tree/master/stable/aws-load-balancer-controller)) |
| Managed add-ons (vpc-cni, kube-proxy, coredns) | not pinned | eksctl picks the default for 1.37. List with `eksctl utils describe-addon-versions --kubernetes-version 1.37` |

## 🚀 Steps
```bash
export AWS_REGION=ap-southeast-1
cd 31-overlay-eksctl/02-secondary-cidr
```

### Stage 0 — default VPC CNI (baseline)
```bash
./scripts/up.sh eks      # profile "eks" (omit for the default profile); pre-flight, cluster, pod subnets, ng-s0, ENIConfigs, controller, app + ALB (about 20 min)
```
It runs `preflight-cidr.sh`, `eksctl create cluster`, `secondary-cidr.sh create` (associates `100.64.0.0/16` and creates the pod subnets), `eksctl create nodegroup` for `ng-s0`, `eniconfig.sh`, the controller Helm install and the app manifests. The ENIConfigs are created now so stage-1 nodes find them at boot.

```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,MAX_PODS:.status.allocatable.pods     # 17
kubectl get eniconfig
kubectl get ingress secondary-cidr-alb -w   # INGRESS_NAME in config.env       # wait for ADDRESS

# Reading helpers (used after every stage)
set -a; . ./config.env; set +a   # CLUSTER_NAME, INGRESS_NAME, ... for the commands below
VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --query 'cluster.resourcesVpcConfig.vpcId' --output text)
free() { aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC_ID \
  --query 'Subnets[].{Subnet:SubnetId,Cidr:CidrBlock,Free:AvailableIpAddressCount}' --output table; }
free        # BASELINE (6 subnets: 2 public + 2 private /27 in 10.100.0.x, 2 pod /20 in 100.64.x.x)

# Hit the default limit
kubectl scale deployment app-deployment --replicas=40
kubectl get pods -l app=app --no-headers | awk '{print $3}' | sort | uniq -c      # some Pending
kubectl get pods -l app=app -o wide | head -5                                      # IPs 10.100.x.x
free        # public subnets lost IPs (pods + warm IPs)
```
Expect: roughly 20–25 app pods fit on 2 nodes (17 per node minus kube-proxy, aws-node, CoreDNS, controller and other system pods), the rest `Pending`. Watch the public `/27` subnets: each starts with 27 usable IPs, and a fully used t3.medium holds 18 (3 ENIs × 6), plus the ALB and any control-plane ENIs. Free IPs drop to single digits, which is the subnet exhaustion this demo is about. If a subnet runs out first, `aws-node` logs `InsufficientFreeAddressesInSubnet` and pods stay `ContainerCreating`.

### Stage 1 — custom networking (secondary CIDR)
```bash
./scripts/stage.sh 1 eks # update vpc-cni, create ng-s1, drain and delete ng-s0 (about 15 min)
kubectl get nodes -o custom-columns=NAME:.metadata.name,MAX_PODS:.status.allocatable.pods     # 12
kubectl get pods -l app=app -o wide | head -5          # IPs now 100.64.x.x
free
```
Expect: pod IPs in `100.64.x.x`; the public subnets' free IPs go **up** (back near baseline), the pod subnets' go down; max pods per node is **12**, so even more pods are `Pending` than in stage 0. The ALB keeps serving because pods are VPC-routable.

### Stage 2 — prefix delegation
```bash
./scripts/stage.sh 2 eks # ENABLE_PREFIX_DELEGATION=true, ng-s2 (maxPods=110) replaces ng-s1
kubectl get nodes -o custom-columns=NAME:.metadata.name,MAX_PODS:.status.allocatable.pods     # 110
kubectl scale deployment app-deployment --replicas=100
kubectl rollout status deployment app-deployment
free
```
AWS recommends **new nodes** when switching a node between single IPs and prefixes (a node holding both reports inconsistent capacity). `stage.sh` creates a new node group and deletes the old one instead of rolling nodes in place.

## 🔍 Validation
```bash
# Pods per node and pod IPs
kubectl get pods -l app=app -o wide --no-headers | awk '{print $7}' | sort | uniq -c
kubectl get pods -l app=app -o wide | head -5

# Pod ENIs live in the secondary subnets, with /28 prefixes in stage 2
aws ec2 describe-network-interfaces \
  --filters Name=vpc-id,Values=$VPC_ID Name=description,Values='aws-K8S-*' \
  --query 'NetworkInterfaces[].{Subnet:SubnetId,Prefixes:Ipv4Prefixes[].Ipv4Prefix}'

# Connectivity
kubectl run client --image=curlimages/curl --restart=Never --command -- sleep 3600
kubectl exec client -- curl -s -o /dev/null -w "pod->internet %{http_code}\n" https://aws.amazon.com/
ALB=$(kubectl get ingress $INGRESS_NAME -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
for i in 1 2 3 4 5; do curl -s -o /dev/null -w "%{http_code}\n" http://$ALB/; done
```
Expected end state (stage 2): 100 Running pods, `MAX_PODS` 110, public-subnet free IPs unchanged by the 100 pods, secondary-subnet free IPs reduced, internet and ALB return `200`.

## 🧹 Cleanup
```bash
./scripts/down.sh eks     # same profile as up.sh; no argument = default profile
```
`down.sh` deletes the Ingress and waits until the ALB is gone, uninstalls the controller, deletes every node group, deletes the pod subnets and disassociates the secondary CIDR (`secondary-cidr.sh delete`, which waits for pod ENIs to disappear and removes leftover detached ones), then runs `eksctl delete cluster --wait`. The ALB and the pod subnets are not owned by eksctl, so they must go first or they block the VPC deletion. `secondary-cidr.sh` only deletes subnets tagged `POD_SUBNET_TAG_KEY=POD_SUBNET_TAG_VALUE` from `config.env` (default `demo=vietvn-secondary-ctl-pods`).

## 🔁 What differs from the Terraform version
| Topic | Terraform | eksctl (this demo) |
|---|---|---|
| Stage switch | `terraform apply -var stage=N` rolls the node group in place | `stage.sh N` creates a new node group and deletes the old one (AWS-recommended for prefixes) |
| vpc-cni env vars | `aws_eks_addon.configuration_values` | `eksctl update addon -f .rendered/addons-sN.yaml` (via `stage.sh`) |
| Secondary CIDR and pod subnets | `aws_vpc_ipv4_cidr_block_association`, `aws_subnet.pods` | `scripts/secondary-cidr.sh` (association + subnets) |
| ENIConfig | `terraform output eniconfig_manifest` | `scripts/eniconfig.sh` (reads subnet IDs with the AWS CLI) |
| Controller IAM | `lbc-iam.tf` + `iam_policy.json` | `podIdentityAssociations` with `wellKnownPolicies` |
| Destroy | `terraform destroy -var stage=2` | `down.sh`: ALB, node groups, pod subnets, then `eksctl delete cluster` |

## 📝 Notes & cost
- **Not tested against a live AWS account.** The eksctl dry run of the rendered `cluster.yaml`, `shellcheck`, the pre-flight script (offline, with sample `describe-vpcs` JSON) and YAML/JSON syntax checks pass. Points that need a real run: the default add-ons coming up with no node group, and the IP headroom of the `/27` public subnets in stage 0 and during each node group swap.
- **Why no explicit subnet CIDRs:** in eksctl, `vpc.subnets` only imports **existing** subnets; listing CIDRs for a new VPC fails with `can't describe subnet by CIDR without VPC ID`. The config sets only `vpc.cidr` and `availabilityZones`; eksctl splits the `/24` (2 AZs → `/27` per subnet, per the [eksctl source](https://github.com/eksctl-io/eksctl/blob/main/pkg/vpc/vpc.go)).
- **`vpc.extraCIDRs` does not associate a CIDR.** In eksctl it only adds an HTTPS ingress rule for that range to the control-plane security group (`pkg/cfn/builder/cluster.go`). Creating a subnet in a range the VPC does not have fails with `InvalidSubnet.Range ... is invalid`. `secondary-cidr.sh` therefore calls `aws ec2 associate-vpc-cidr-block`, waits for `associated`, then creates the subnets. `cluster.yaml` keeps `extraCIDRs` only for that security group rule.
- **Small subnets and the ALB:** an ALB needs subnets of at least `/27` with at least 8 free IPs ([ALB subnets](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/application-load-balancers.html#subnets-load-balancer)). The ALB is created in stage 0 before scaling, while the subnets still have room. When stage 0 drains a public subnet below 8 free IPs, AWS warns the ALB may fail to scale or replace nodes and return 5xx errors. Treat that as part of the lesson, and move to stage 1 (which gives the IPs back) instead of leaving the cluster in that state.
- **Formula:** `maxPods = ENIs × (IPs per ENI − 1) + 2`. Custom networking removes the primary ENI from the pod pool: `(ENIs − 1) × (IPs − 1) + 2`. Verify the numbers for your type with `aws ec2 describe-instance-types` (see `24-max-pod`).
- **Set `maxPods` explicitly in stage 1** (`maxPodsPerNode: 12`). Otherwise kubelet keeps the ENI-formula default of 17 and over-commits a node that can only hand out 12 pod IPs.
- Custom networking is IPv4 only and cannot be combined with an IPv6 cluster. AWS suggests IPv6 as the first option if you only need more IPs; this demo does not cover it ([EKS custom networking](https://docs.aws.amazon.com/eks/latest/userguide/cni-custom-network.html), [IP optimization best practices](https://docs.aws.amazon.com/eks/latest/best-practices/ip-opt.html)).
- Prefix delegation is supported together with custom networking ([best practices](https://docs.aws.amazon.com/eks/latest/best-practices/ip-opt.html), [prefix delegation](https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html)). Each prefix is 16 IPs, so a pod subnet needs room for contiguous `/28` blocks.
- The pod subnets deliberately have no `kubernetes.io/role/cni` tag, so VPC CNI subnet discovery does not pick them up on its own. Only the ENIConfigs steer pods there.
- Pod traffic to the internet is SNAT'd to the node's primary IP, so the pod subnets need no internet route and no NAT gateway.
- **Cost:** EKS control plane, 2 EC2 instances and an ALB bill hourly ([EKS](https://aws.amazon.com/eks/pricing/), [EC2](https://aws.amazon.com/ec2/pricing/on-demand/), [ELB](https://aws.amazon.com/elasticloadbalancing/pricing/)). Run the cleanup.
