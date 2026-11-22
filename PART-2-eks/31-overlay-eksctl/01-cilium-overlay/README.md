# 31 / 01 — Cilium overlay with eksctl: pods that use zero VPC subnet IPs

## 🎯 Scenario
Same demo as [`30-no-vpc-ip-pods/01-cilium-overlay`](../../30-no-vpc-ip-pods/01-cilium-overlay/README.md), built with **eksctl** instead of Terraform. One command creates the VPC, cluster, node group and IAM, and one command deletes all of it.

With the default VPC CNI every pod takes an IP from a VPC subnet, and the instance's ENI limit caps pods per node (`24-max-pod`: t3.medium = 17). Here Cilium runs in **overlay (VXLAN) mode**: pods get IPs from a private pool (`192.168.0.0/16`) that never touches the VPC. The subnets only hold the nodes and the ALB, and pods per node are capped by kubelet `maxPods` (110), not by ENIs.

## 🗺 Architecture
```
VPC 10.100.0.0/24  (eksctl-managed, IGW, NO NAT gateway; eksctl splits it into 8 x /27, 27 usable IPs each)
 ├─ public  10.100.0.0/27  (ap-southeast-1a) ── node 1 (t3.medium, public IP) ── pods 192.168.0.0/24 ┐ VXLAN
 ├─ public  10.100.0.32/27 (ap-southeast-1b) ── node 2 (t3.medium, public IP) ── pods 192.168.1.0/24 ┘
 ├─ private 10.100.0.64/27, 10.100.0.96/27   (created by eksctl, no NAT, no nodes; control-plane ENIs may sit here)
 └─ 10.100.0.128/25 left free
 ALB (internet-facing) ──► node:NodePort ──► kube-proxy ──► pod (overlay)

EKS cluster  vietvn-overlay-ctl  (Kubernetes 1.37, no vpc-cni add-on, Cilium chart 1.20.5)
```

| File | Purpose |
|---|---|
| `config.env` | **All values** (names, CIDRs, sizes, versions). Edit this file only |
| `cluster.yaml` | `/24` VPC (eksctl splits it), control plane, `disableDefaultAddons`, kube-proxy and Pod Identity agent add-ons |
| `pod-identity.yaml` | IAM role + Pod Identity association for the AWS Load Balancer Controller |
| `nodegroup.yaml` | Managed node group: `maxPodsPerNode: 110`, Cilium taint, no CNI policy |
| `manifests/` | Cilium and controller Helm values, app, IngressClass, ALB Ingress |
| `scripts/up.sh`, `scripts/down.sh` | Build (re-runnable, finished steps are skipped) and delete everything in the right order |
| `scripts/render.sh` | Render the templates into `.rendered/` without AWS calls |

**Why three eksctl files:** eksctl refuses node groups and Pod Identity associations in the same file as a cluster created without the VPC CNI ("remove these fields and add them back after cluster creation"). It also keeps the order explicit: Cilium must exist before nodes join, because nodes stay `NotReady` without a CNI.

## ⚙️ Configuration
All names, CIDRs, sizes and versions live in **`config.env`** (cluster name, region, Kubernetes version, AZs, VPC/service/pod CIDRs, node group size and `maxPods`, controller role name, Ingress/ALB names, chart versions). Change a value there only.

The `*.yaml` files are **templates** with `${VAR}` placeholders. Every script first renders them into `.rendered/` (git-ignored) from `config.env`, and fails if a placeholder has no value. `up.sh` also checks that the VPC, service and pod CIDRs do not overlap. Run `./scripts/render.sh` to render without touching AWS, for example before following the step-by-step commands. Shared helpers are in `../lib/common.sh`.

## ✅ Prerequisites
- An AWS CLI profile, region `ap-southeast-1`. `up.sh` and `down.sh` take the profile as an optional argument; without it the default AWS profile is used (`AWS_PROFILE` if set, otherwise `[default]`).
- `eksctl` (latest is 0.232.0; the dry run was checked with 0.229.0-dev, which accepts `1.37`. Verify yours with `./scripts/render.sh && eksctl create cluster -f .rendered/cluster.yaml --dry-run`), `kubectl`, `helm`, `jq`, `aws`.
- Permissions to create VPC, EKS, IAM roles/policies, CloudFormation, EC2 and ELB resources.

### Version compatibility (checked November 2026)
| Component | Version used | Status |
|---|---|---|
| EKS Kubernetes | `1.37` | Available, standard support until 2027-12-01 ([EKS versions](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html)) |
| Node AMI | AL2023 | Default for managed node groups on 1.30+. The 1.37 kubelet changes do not affect EKS-optimized AMIs ([1.37 notes](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions-standard.html)) |
| AWS Load Balancer Controller chart | `3.6.3` | Current chart ([eks-charts](https://github.com/aws/eks-charts/tree/master/stable/aws-load-balancer-controller)) |
| Cilium chart | `1.20.5` | Latest release, but its docs list e2e-tested Kubernetes only up to 1.36 and its EKS CI covers 1.33 to 1.35 ([compatibility](https://docs.cilium.io/en/stable/network/kubernetes/compatibility/)). **Unverified on 1.37.** |
| Managed add-ons | not pinned | eksctl picks the default version for 1.37. List with `eksctl utils describe-addon-versions --kubernetes-version 1.37` |

If Cilium misbehaves on 1.37 (nodes stay `NotReady`, `cilium-dbg status` not OK), change `version` to `"1.36"` in `cluster.yaml` and `nodegroup.yaml` and rebuild.

## 🚀 Steps
Everything at once:
```bash
cd 31-overlay-eksctl/01-cilium-overlay
./scripts/up.sh eks      # profile "eks"; about 20-25 minutes
./scripts/up.sh          # or: default AWS profile
```

Or step by step (this is what `up.sh` runs). The commands read the values from `config.env`:
```bash
cd 31-overlay-eksctl/01-cilium-overlay
set -a; . ./config.env; set +a; export AWS_REGION=$REGION
./scripts/render.sh           # templates -> .rendered/

# 1. VPC + control plane + kube-proxy / pod-identity add-ons, no nodes (about 15 min)
eksctl create cluster -f .rendered/cluster.yaml
kubectl get ns                                   # API reachable, no nodes yet

# 2. IAM for the AWS Load Balancer Controller (EKS Pod Identity)
eksctl create podidentityassociation -f .rendered/pod-identity.yaml

# 3. Cilium in overlay mode, BEFORE any node joins
helm repo add cilium https://helm.cilium.io/ && helm repo update
helm install cilium cilium/cilium --version $CILIUM_VERSION \
  --namespace kube-system -f .rendered/manifests/cilium-values.yaml

# 4. Node group (tainted until Cilium is ready, maxPods=110) and CoreDNS (about 5 min)
eksctl create nodegroup -f .rendered/nodegroup.yaml
eksctl create addon --cluster $CLUSTER_NAME --name coredns
```

Check the cluster is healthy:
```bash
kubectl get nodes -o wide                       # Ready, EXTERNAL-IP set (public)
kubectl get nodes -o custom-columns=NAME:.metadata.name,MAX_PODS:.status.allocatable.pods,TAINTS:.spec.taints
# MAX_PODS = 110, the agent-not-ready taint is gone
kubectl -n kube-system exec ds/cilium -- cilium-dbg status --brief   # OK
kubectl -n kube-system exec ds/cilium -- cilium-dbg status | grep -i -E "IPAM|Routing|Masquerading"
kubectl get pods -n kube-system -o wide         # coredns pods have 192.168.x.x IPs
```

Install the AWS Load Balancer Controller. It **must** run with `hostNetwork` because the EKS control plane cannot route to overlay pod IPs and calls the controller's webhooks:
```bash
VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --query 'cluster.resourcesVpcConfig.vpcId' --output text)
helm repo add eks https://aws.github.io/eks-charts && helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --version $LBC_CHART_VERSION -n kube-system \
  -f .rendered/manifests/lbc-values.yaml --set vpcId=$VPC_ID
kubectl -n kube-system rollout status deploy/aws-load-balancer-controller
```
IAM comes from the Pod Identity association created in step 2 for `kube-system/aws-load-balancer-controller`.

Deploy the app and the ALB, then take the "before" reading:
```bash
kubectl apply -f .rendered/manifests/01-app.yaml -f .rendered/manifests/02-ingress-class.yaml -f .rendered/manifests/03-alb.yaml
kubectl get ingress $INGRESS_NAME -w              # wait for ADDRESS (about 2-3 min)

# BEFORE: free IPs in the subnets (the ALB already took its few IPs)
aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC_ID \
  --query 'Subnets[].{Subnet:SubnetId,Cidr:CidrBlock,Free:AvailableIpAddressCount}' --output table
```

Scale far past the default ENI limit (2 × 17 = 34 pods for t3.medium):
```bash
kubectl scale deployment app-deployment --replicas=100
kubectl rollout status deployment app-deployment
```

## 🔍 Validation
```bash
# 1. All 100 pods Running, none Pending
kubectl get pods -l app=app --no-headers | awk '{print $3}' | sort | uniq -c

# 2. Pod IPs are in 192.168.0.0/16 (not 10.100.x.x), spread over both nodes
kubectl get pods -l app=app -o wide --no-headers | awk '{print $7}' | sort | uniq -c    # pods per node (~50 each)
kubectl get pods -l app=app -o wide | head -5

# 3. AFTER: free IPs in the subnets must equal the BEFORE reading
aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC_ID \
  --query 'Subnets[].{Subnet:SubnetId,Cidr:CidrBlock,Free:AvailableIpAddressCount}' --output table

# 4. No pod ENIs: the VPC CNI names the ENIs it creates "aws-K8S-<instance-id>"
aws ec2 describe-network-interfaces \
  --filters Name=vpc-id,Values=$VPC_ID Name=description,Values='aws-K8S-*' \
  --query 'NetworkInterfaces[].NetworkInterfaceId'                                  # expect []

# 5. Pod -> pod across nodes
kubectl run client --image=curlimages/curl --restart=Never --command -- sleep 3600
OTHER=$(kubectl get pods -l app=app -o wide --no-headers | awk -v n=$(kubectl get pod client -o jsonpath='{.spec.nodeName}') '$7!=n{print $6; exit}')
kubectl exec client -- curl -s -o /dev/null -w "pod->pod %{http_code}\n" http://$OTHER:8080/

# 6. Pod -> internet (SNAT to the node's public IP; no NAT gateway exists)
kubectl exec client -- curl -s -o /dev/null -w "pod->internet %{http_code}\n" https://aws.amazon.com/

# 7. ALB (instance targets, NodePort)
ALB=$(kubectl get ingress $INGRESS_NAME -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
for i in 1 2 3 4 5; do curl -s -o /dev/null -w "%{http_code}\n" http://$ALB/; done
```
Expected: 100 Running pods on 2 nodes, pod IPs in `192.168.x.x`, **identical free-IP counts before and after scaling**, `pod->pod 200`, `pod->internet 200`, ALB returns `200`.

## 🧹 Cleanup
One command (deletes the ALB first, then the cluster and VPC):
```bash
./scripts/down.sh eks     # same profile as up.sh; no argument = default profile
```
`down.sh` runs: delete the Ingress and wait until the ALB is gone, `helm uninstall` the controller, then `eksctl delete cluster --name $CLUSTER_NAME --wait`. The ALB must go first: its ENIs and security groups are created by the controller, not by eksctl, and they block the VPC deletion.

Verify nothing is left:
```bash
eksctl get cluster --region ap-southeast-1
aws cloudformation list-stacks --stack-status-filter DELETE_FAILED --query 'StackSummaries[?contains(StackName, `vietvn-overlay-ctl`)].StackName'
```

## 🔁 What differs from the Terraform version
| Topic | Terraform (`30-.../01-cilium-overlay`) | eksctl (this demo) |
|---|---|---|
| Phases | `apply`, Helm Cilium, `apply -var create_nodes=true` | `create cluster`, Helm Cilium, `create nodegroup` |
| Config files | 7 `.tf` files + shared `iam_policy.json` | 3 eksctl files, no policy JSON (`wellKnownPolicies`) |
| Node `maxPods` and taint | launch template with nodeadm user data | `maxPodsPerNode`, `taints` |
| Node IAM role | explicit role without `AmazonEKS_CNI_Policy` | `iam.attachPolicyARNs` without it |
| Destroy | `terraform destroy`, state file to keep | `eksctl delete cluster`, CloudFormation stacks |
| State | local `terraform.tfstate` | CloudFormation (no local state) |

## 📝 Notes & cost
- **Why no explicit subnet CIDRs:** in eksctl, `vpc.subnets` only imports **existing** subnets. Listing CIDRs for a new VPC fails with `can't describe subnet by CIDR without VPC ID`, so the config sets only `vpc.cidr` and `availabilityZones`, and eksctl splits the `/24` itself (2 AZs → `/27` per subnet, per the [eksctl source](https://github.com/eksctl-io/eksctl/blob/main/pkg/vpc/vpc.go)).
- **Not tested against a live AWS account.** The eksctl dry run of the rendered `cluster.yaml`, `shellcheck`, template rendering and Helm rendering pass. Report any behavior that differs from this README.
- **Limits of the overlay** (from the [Cilium EKS guide](https://docs.cilium.io/en/stable/installation/k8s-install-helm/)): pod traffic to the VPC or AWS services is SNAT'd to the node IP; the EKS API server cannot reach pod IPs, so any webhook pod must be `hostNetwork` or exposed through a Service. Pods are not routable from the VPC, so ALB targets must be `instance` (NodePort), never `ip`.
- **VPC peering:** the pod range `192.168.0.0/16` is not a VPC CIDR, so a peering connection only compares `10.100.0.0/24`. A peer VPC that uses `192.168.0.0/16` does not block it. Pods reach the peer through SNAT to the node IP.
- **Pod CIDR:** Cilium's default pool is `10.0.0.0/8`, which overlaps a 10.x VPC. The values file sets `192.168.0.0/16`; keep it disjoint from the VPC and the EKS service CIDR (`172.20.0.0/16`).
- **Support:** the VPC CNI is the only CNI AWS supports on EC2 nodes. Cilium is a partner-supported option ([EKS alternate CNIs](https://docs.aws.amazon.com/eks/latest/userguide/alternate-cni-plugins.html)). EKS Auto Mode does not support alternate CNIs.
- **MTU:** VXLAN adds encapsulation overhead. Test large transfers if you tune MTU.
- **Public subnets, no NAT:** the nodes have public IPs and a wide-open egress path for this demo only. Use private subnets and NAT or VPC endpoints for anything real.
- **Cost:** you pay hourly for the EKS control plane, 2 EC2 instances and the ALB ([EKS pricing](https://aws.amazon.com/eks/pricing/), [EC2 pricing](https://aws.amazon.com/ec2/pricing/on-demand/), [ELB pricing](https://aws.amazon.com/elasticloadbalancing/pricing/)). Run the cleanup when done. There is no NAT gateway.
