# 30 / 01 — Cilium overlay: pods that use zero VPC subnet IPs

## 🎯 Scenario
With the default VPC CNI every pod takes an IP from a VPC subnet, and the instance's ENI limit caps pods per node (`24-max-pod`: t3.medium = 17). Here Cilium runs in **overlay (VXLAN) mode**: pods get IPs from a private pool (`192.168.0.0/16`) that never touches the VPC. The subnets only hold the nodes and the ALB, and pods per node are capped by kubelet `maxPods` (110), not by ENIs.

## 🗺 Architecture
```
VPC 10.0.0.0/16  (public subnets only, IGW, NO NAT gateway)
 ├─ public-0 10.0.0.0/24 (AZ a) ── node 1 (t3.medium, public IP) ── pods 192.168.0.0/24 ┐ VXLAN
 └─ public-1 10.0.1.0/24 (AZ b) ── node 2 (t3.medium, public IP) ── pods 192.168.1.0/24 ┘
 ALB (internet-facing) ──► node:NodePort ──► kube-proxy ──► pod (overlay)

EKS cluster  vietvn-overlay  (k8s 1.37, no vpc-cni add-on, Cilium chart 1.20.5)
```
Created by Terraform: VPC, 2 public subnets, IGW, EKS cluster, managed node group, kube-proxy / CoreDNS / Pod Identity agent add-ons, and the IAM role for the AWS Load Balancer Controller (EKS Pod Identity).
Installed by Helm/kubectl: Cilium, AWS Load Balancer Controller, the app.

## ✅ Prerequisites
- AWS CLI profile `eks`, region `ap-southeast-1` (change in `terraform/variables.tf`).
- `terraform` ≥ 1.5, `kubectl`, `helm`, `jq`.
- Permissions to create VPC, EKS, IAM roles/policies, EC2 and ELB resources.

## 🚀 Steps
Two Terraform phases are needed: Cilium must be installed after the control plane exists and **before** nodes join (nodes stay `NotReady` without a CNI).

```bash
cd 30-no-vpc-ip-pods/01-cilium-overlay/terraform

# Phase 1: VPC + control plane + IAM + kube-proxy / pod-identity add-ons (about 10 min)
terraform init
terraform apply

# kubeconfig
eval "$(terraform output -raw kubeconfig_command)"
kubectl get ns                      # API reachable, no nodes yet

# Install Cilium in overlay mode (values: ../manifests/cilium-values.yaml)
helm repo add cilium https://helm.cilium.io/ && helm repo update
helm install cilium cilium/cilium --version 1.20.5 \
  --namespace kube-system -f ../manifests/cilium-values.yaml

# Phase 2: node group (tainted, maxPods=110) + CoreDNS (about 5 min)
terraform apply -var create_nodes=true
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
helm repo add eks https://aws.github.io/eks-charts && helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --version 3.6.3 -n kube-system \
  -f ../manifests/lbc-values.yaml \
  --set vpcId=$(terraform output -raw vpc_id)
kubectl -n kube-system rollout status deploy/aws-load-balancer-controller
```
IAM comes from the Pod Identity association that Terraform created for `kube-system/aws-load-balancer-controller`.

Deploy the app and the ALB, then take the "before" reading:
```bash
kubectl apply -f ../manifests/01-app.yaml -f ../manifests/02-ingress-class.yaml -f ../manifests/03-alb.yaml
kubectl get ingress overlay-alb -w              # wait for ADDRESS (about 2-3 min)

# BEFORE: free IPs in the subnets (the ALB already took its few IPs)
SUBNETS=$(terraform output -json public_subnet_ids | jq -r 'join(" ")')
aws ec2 describe-subnets --subnet-ids $SUBNETS --profile eks \
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

# 2. Pod IPs are in 192.168.0.0/16 (not 10.0.x.x), spread over both nodes
kubectl get pods -l app=app -o wide --no-headers | awk '{print $7}' | sort | uniq -c    # pods per node (~50 each)
kubectl get pods -l app=app -o wide | head -5

# 3. AFTER: free IPs in the subnets must equal the BEFORE reading
aws ec2 describe-subnets --subnet-ids $SUBNETS --profile eks \
  --query 'Subnets[].{Subnet:SubnetId,Cidr:CidrBlock,Free:AvailableIpAddressCount}' --output table

# 4. No pod ENIs: the VPC CNI names the ENIs it creates "aws-K8S-<instance-id>"
aws ec2 describe-network-interfaces --profile eks \
  --filters Name=vpc-id,Values=$(terraform output -raw vpc_id) Name=description,Values='aws-K8S-*' \
  --query 'NetworkInterfaces[].NetworkInterfaceId'                                  # expect []

# 5. Pod -> pod across nodes
kubectl run client --image=curlimages/curl --restart=Never --command -- sleep 3600
OTHER=$(kubectl get pods -l app=app -o wide --no-headers | awk -v n=$(kubectl get pod client -o jsonpath='{.spec.nodeName}') '$7!=n{print $6; exit}')
kubectl exec client -- curl -s -o /dev/null -w "pod->pod %{http_code}\n" http://$OTHER:8080/

# 6. Pod -> internet (SNAT to the node's public IP; no NAT gateway exists)
kubectl exec client -- curl -s -o /dev/null -w "pod->internet %{http_code}\n" https://aws.amazon.com/

# 7. ALB (instance targets, NodePort)
ALB=$(kubectl get ingress overlay-alb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
for i in 1 2 3 4 5; do curl -s -o /dev/null -w "%{http_code}\n" http://$ALB/; done
```
Expected: 100 Running pods on 2 nodes, pod IPs in `192.168.x.x`, **identical free-IP counts before and after scaling**, `pod->pod 200`, `pod->internet 200`, ALB returns `200`.

## 🧹 Cleanup
Delete the ALB first, otherwise its ENIs/security groups block the VPC deletion.
```bash
kubectl delete -f ../manifests/03-alb.yaml
kubectl delete -f ../manifests/01-app.yaml -f ../manifests/02-ingress-class.yaml
kubectl delete pod client
helm uninstall aws-load-balancer-controller -n kube-system
# wait until the ALB is gone (EC2 console, or: aws elbv2 describe-load-balancers --profile eks)
terraform destroy -var create_nodes=true
```

## 📝 Notes & cost
- **Limits of the overlay** (from the [Cilium EKS guide](https://docs.cilium.io/en/stable/installation/k8s-install-helm/)): pod traffic to the VPC or AWS services is SNAT'd to the node IP; the EKS API server cannot reach pod IPs, so any webhook pod must be `hostNetwork` or exposed through a Service. Pods are not routable from the VPC, so ALB targets must be `instance` (NodePort), never `ip`.
- **Pod CIDR:** Cilium's default pool is `10.0.0.0/8`, which overlaps a 10.x VPC. The values file sets `192.168.0.0/16`; keep it disjoint from the VPC and the EKS service CIDR (`172.20.0.0/16`).
- **Support:** the VPC CNI is the only CNI AWS supports on EC2 nodes. Cilium is a partner-supported option, so plan for commercial support or in-house expertise ([EKS alternate CNIs](https://docs.aws.amazon.com/eks/latest/userguide/alternate-cni-plugins.html)). EKS Auto Mode does not support alternate CNIs.
- **MTU:** VXLAN adds encapsulation overhead. Test large transfers if you tune MTU.
- **Public subnets, no NAT:** the nodes have public IPs and a wide-open egress path for this demo only. Use private subnets and NAT or VPC endpoints for anything real.
- **Cost:** you pay hourly for the EKS control plane, 2 EC2 instances and the ALB ([EKS pricing](https://aws.amazon.com/eks/pricing/), [EC2 pricing](https://aws.amazon.com/ec2/pricing/on-demand/), [ELB pricing](https://aws.amazon.com/elasticloadbalancing/pricing/)). Run the cleanup when done. There is no NAT gateway.
