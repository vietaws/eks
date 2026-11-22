# 30 / 02 — VPC CNI custom networking (secondary CIDR) + prefix delegation

## 🎯 Scenario
Keep the AWS VPC CNI (fully AWS-supported) but move pod IPs out of your main subnets into a **secondary VPC CIDR** (`100.64.0.0/16`). Pods stay VPC-routable, so ALB `ip` targets and webhooks work unchanged.

The catch the demo proves: custom networking alone **lowers** pods per node (the primary ENI no longer serves pods). To go above the default limit you also enable **prefix delegation**. The demo walks one cluster through three stages:

| Stage | Setting | Pod IPs come from | t3.medium max pods |
|---|---|---|---|
| 0 | default VPC CNI (same as `24-max-pod`) | primary subnets `10.0.x.x` | 17 = 3×(6−1)+2 |
| 1 | + custom networking | secondary subnets `100.64.x.x` | 12 = (3−1)×(6−1)+2 |
| 2 | + prefix delegation, `maxPods=110` | `/28` prefixes of the secondary subnets | 110 |

Honest framing: pods still consume **VPC IPs**, but from the secondary CIDR. Your main (routable, scarce) subnets are spared.

## 🗺 Architecture
```
VPC 10.0.0.0/16 + secondary 100.64.0.0/16 (public subnets only, IGW, NO NAT gateway)
 ├─ public-0 10.0.0.0/24  (AZ a)  node 1 primary ENI, ALB     ┐ ENIConfig "AZ a"
 ├─ public-1 10.0.1.0/24  (AZ b)  node 2 primary ENI, ALB     ┘ ENIConfig "AZ b"
 ├─ pods-0   100.64.0.0/20 (AZ a) pod ENIs of node 1
 └─ pods-1   100.64.16.0/20 (AZ b) pod ENIs of node 2
ALB (internet-facing, target-type ip) ──► pod IP (100.64.x.x)

EKS cluster  vietvn-secondary  (k8s 1.37, managed add-ons vpc-cni / kube-proxy / coredns / pod-identity-agent)
```
Created by Terraform: VPC + secondary CIDR, subnets, IGW, cluster, node group, add-ons, LBC IAM role (Pod Identity). The `stage` variable switches the vpc-cni add-on env vars and the kubelet `maxPods`; changing it rolls the nodes.
Installed by Helm/kubectl: ENIConfigs, AWS Load Balancer Controller, app.

## ✅ Prerequisites
- AWS CLI profile `eks`, region `ap-southeast-1`; `terraform` ≥ 1.5, `kubectl`, `helm`, `jq`.
- Read `24-max-pod` first (stage 0 repeats it).

## 🚀 Steps

### Stage 0 — default VPC CNI (baseline)
```bash
cd 30-no-vpc-ip-pods/02-secondary-cidr/terraform
terraform init
terraform apply -var stage=0            # about 15 min
eval "$(terraform output -raw kubeconfig_command)"
kubectl get nodes -o custom-columns=NAME:.metadata.name,MAX_PODS:.status.allocatable.pods     # 17

# ENIConfig per AZ (CRD comes from the vpc-cni add-on). Create them NOW so stage 1 nodes find them at boot.
terraform output -raw eniconfig_manifest | kubectl apply -f -
kubectl get eniconfig

# AWS Load Balancer Controller (normal install, Pod Identity role created by Terraform)
helm repo add eks https://aws.github.io/eks-charts && helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --version 3.6.3 -n kube-system -f ../manifests/lbc-values.yaml \
  --set vpcId=$(terraform output -raw vpc_id)
kubectl -n kube-system rollout status deploy/aws-load-balancer-controller

# App + ALB (target-type ip)
kubectl apply -f ../manifests/01-app.yaml -f ../manifests/02-ingress-class.yaml -f ../manifests/03-alb.yaml

# Reading helpers (used after every stage)
PRIMARY=$(terraform output -json primary_subnet_ids | jq -r 'join(" ")')
PODS=$(terraform output -json pod_subnet_ids | jq -r 'join(" ")')
free() { aws ec2 describe-subnets --profile eks --subnet-ids $PRIMARY $PODS \
  --query 'Subnets[].{Subnet:SubnetId,Cidr:CidrBlock,Free:AvailableIpAddressCount}' --output table; }
free        # BASELINE

# Hit the default limit
kubectl scale deployment app-deployment --replicas=40
kubectl get pods -l app=app --no-headers | awk '{print $3}' | sort | uniq -c      # some Pending
kubectl get pods -l app=app -o wide | head -5                                      # IPs 10.0.x.x
free        # primary subnets lost IPs (pods + warm IPs)
```
Expect: roughly 20–25 app pods fit on 2 nodes (17 per node minus kube-proxy, aws-node, CoreDNS, LBC and other system pods), the rest `Pending`.

### Stage 1 — custom networking (secondary CIDR)
```bash
terraform apply -var stage=1            # updates vpc-cni env, then rolls nodes one at a time (about 15 min)
kubectl get nodes -o custom-columns=NAME:.metadata.name,MAX_PODS:.status.allocatable.pods     # 12
kubectl get pods -l app=app -o wide | head -5          # IPs now 100.64.x.x
free
```
Expect: pod IPs in `100.64.x.x`; the primary subnets' free IPs go **up** (back near baseline), the pod subnets' go down; max pods per node is **12**, so even more pods are `Pending` than in stage 0. The ALB keeps serving because pods are VPC-routable.

### Stage 2 — prefix delegation
```bash
terraform apply -var stage=2            # ENABLE_PREFIX_DELEGATION=true, maxPods=110, nodes rolled again
kubectl get nodes -o custom-columns=NAME:.metadata.name,MAX_PODS:.status.allocatable.pods     # 110
kubectl scale deployment app-deployment --replicas=100
kubectl rollout status deployment app-deployment
free
```
AWS recommends **new nodes** when switching a node between single IPs and prefixes (a node holding both reports inconsistent capacity). The stage change replaces every node, so this holds.

## 🔍 Validation
```bash
# Pods per node and pod IPs
kubectl get pods -l app=app -o wide --no-headers | awk '{print $7}' | sort | uniq -c
kubectl get pods -l app=app -o wide | head -5

# Pod ENIs live in the secondary subnets, with /28 prefixes in stage 2
aws ec2 describe-network-interfaces --profile eks \
  --filters Name=vpc-id,Values=$(terraform output -raw vpc_id) Name=description,Values='aws-K8S-*' \
  --query 'NetworkInterfaces[].{Subnet:SubnetId,Prefixes:Ipv4Prefixes[].Ipv4Prefix}'

# Connectivity
kubectl run client --image=curlimages/curl --restart=Never --command -- sleep 3600
kubectl exec client -- curl -s -o /dev/null -w "pod->internet %{http_code}\n" https://aws.amazon.com/
ALB=$(kubectl get ingress secondary-cidr-alb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
for i in 1 2 3 4 5; do curl -s -o /dev/null -w "%{http_code}\n" http://$ALB/; done
```
Expected end state (stage 2): 100 Running pods, `MAX_PODS` 110, primary-subnet free IPs unchanged by the 100 pods, secondary-subnet free IPs reduced, internet and ALB return `200`.

## 🧹 Cleanup
```bash
kubectl delete -f ../manifests/03-alb.yaml           # wait until the ALB is gone
kubectl delete -f ../manifests/01-app.yaml -f ../manifests/02-ingress-class.yaml
kubectl delete pod client
helm uninstall aws-load-balancer-controller -n kube-system
terraform destroy -var stage=2
```

## 📝 Notes & cost
- **Formula:** `maxPods = ENIs × (IPs per ENI − 1) + 2`. Custom networking removes the primary ENI from the pod pool: `(ENIs − 1) × (IPs − 1) + 2`. Verify the numbers for your type with `aws ec2 describe-instance-types` (see `24-max-pod`).
- **Set `maxPods` explicitly in stage 1.** Otherwise kubelet keeps the ENI-formula default of 17 and over-commits a node that can only hand out 12 pod IPs.
- Custom networking is IPv4 only and cannot be combined with an IPv6 cluster. AWS suggests IPv6 as the first option if you only need more IPs ([EKS custom networking](https://docs.aws.amazon.com/eks/latest/userguide/cni-custom-network.html), [IP optimization best practices](https://docs.aws.amazon.com/eks/latest/best-practices/ip-opt.html)).
- Prefix delegation is supported together with custom networking ([best practices](https://docs.aws.amazon.com/eks/latest/best-practices/ip-opt.html), [prefix delegation](https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html)). Each prefix is 16 IPs, so a pod subnet needs room for contiguous `/28` blocks.
- The secondary subnets deliberately have no `kubernetes.io/role/cni` tag, so VPC CNI subnet discovery does not pick them up on its own. Only the ENIConfigs steer pods there.
- Pod traffic to the internet is SNAT'd to the node's primary IP, so the pod subnets need no internet route and no NAT gateway.
- **Cost:** EKS control plane, 2 EC2 instances and an ALB bill hourly ([EKS](https://aws.amazon.com/eks/pricing/), [EC2](https://aws.amazon.com/ec2/pricing/on-demand/), [ELB](https://aws.amazon.com/elasticloadbalancing/pricing/)). Run the cleanup.
