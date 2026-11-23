# 32.01 — EKS Auto Mode: what AWS runs for you

## 🎯 Scenario
Create a cluster with **no node group and no add-ons**, deploy a web app, a load balancer and an EBS volume, and see compute, networking, load balancing, DNS and storage appear without installing anything.

## 🗺 Architecture
```
kubectl apply ─► pod Pending ─► Auto Mode (managed Karpenter) launches an EC2 node ─► pod Running
Service type=LoadBalancer ─► built-in load balancing capability ─► NLB
PVC (auto-ebs-sc)         ─► built-in block storage capability  ─► EBS gp3 volume
```
| Capability | Self-managed equivalent you would install | On Auto Mode |
|------------|-------------------------------------------|--------------|
| Node provisioning | Karpenter (Helm, IAM, SQS queue) | built in, `NodePool` + `NodeClass` CRDs |
| Pod networking | Amazon VPC CNI add-on | built in |
| Cluster DNS / kube-proxy | CoreDNS + kube-proxy add-ons | built in |
| Load balancers | AWS Load Balancer Controller (Helm, IAM) | built in |
| Block storage | EBS CSI driver add-on | built in (you create the StorageClass) |
| Pod Identity agent | `eks-pod-identity-agent` add-on | built in |
| Spot / health / maintenance events | Karpenter + SQS + EventBridge | built in |

## ✅ Prerequisites
- `eksctl` ≥ 0.230.0, `kubectl`, `aws` CLI with a profile that can create EKS/VPC/IAM resources.
- Nothing else. No Helm charts are installed in this demo.

## 🚀 Steps
```bash
export AWS_REGION=ap-southeast-1 CLUSTER_NAME=eksauto
(cd ../../02-create-eks-cluster && ./scripts/up.sh --mode=auto)       # about 15-20 min
```

### 1. An empty cluster that is ready to schedule
```bash

# No resources found: Auto Mode creates nodes on demand
kubectl get nodes                               

# Check EC2 Instance created by Auto-Mode
aws ec2 describe-instances --include-managed-resources

# general-purpose, system (built in, you cannot edit them)
kubectl get nodepools                           
kubectl get nodeclasses                         # default

# nothing: no aws-node, kube-proxy, coredns, karpenter or LB controller pods

kubectl get pods,ds,deploy -A                   
kubectl get nodepool general-purpose -o yaml | grep -A12 -E 'disruption|expireAfter'
```

### 2. Compute: a pending pod gets a node
```bash
kubectl apply -f manifests/01-app.yaml

# Pending, then ContainerCreating, then Running (about 1 minute)
kubectl get pods -w                             
kubectl get nodeclaims,nodes -o wide
kubectl get nodes -L eks.amazonaws.com/compute-type,node.kubernetes.io/instance-type,karpenter.sh/capacity-type
```
The node carries `eks.amazonaws.com/compute-type=auto`. Look at the `OS-IMAGE` column: it is an AWS-managed, immutable image. There is no SSH and no SSM on these nodes.

### 3. Load balancing: Service → NLB
```bash
kubectl get svc home -w                         # EXTERNAL-IP shows an NLB DNS name after 2-3 minutes
curl -s "http://$(kubectl get svc home -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')" | head -5
```

### 4. Storage: PVC → EBS volume
```bash
kubectl apply -f manifests/00-storageclass.yaml -f manifests/02-pvc-app.yaml
kubectl get pvc,pv                              # Bound once the pod is scheduled (WaitForFirstConsumer)
kubectl logs deploy/writer                      # prints the date written to the volume
kubectl delete pod -l app=writer; sleep 20; kubectl logs deploy/writer   # two lines: the data survived
```

### 5. Scale out and in
```bash
kubectl apply -f manifests/03-inflate.yaml
kubectl scale deployment inflate --replicas 6
kubectl get nodeclaims -w                       # new nodes appear
kubectl scale deployment inflate --replicas 0   # empty nodes are consolidated after a short delay
```

### 6. See the lifetime and disruption defaults
```bash
kubectl get nodepool general-purpose -o jsonpath='{.spec.template.spec.expireAfter}{"\n"}{.spec.disruption}{"\n"}'
kubectl get nodes -o custom-columns=NAME:.metadata.name,CREATED:.metadata.creationTimestamp
```
Defaults per the AWS docs: underutilized nodes are consolidated, nodes are terminated after 336 hours (maximum 21 days), a disruption budget of 10% of nodes applies, and nodes drift when a new Auto Mode AMI is released, roughly weekly.

## 🔍 Validation
| Check | Expected |
|-------|----------|
| `kubectl get pods -A` right after creation | No add-on pods for CNI, DNS, proxy, LB controller or Karpenter |
| `kubectl get svc home` | NLB hostname, and `curl` returns the app page |
| `kubectl get pvc data` | `Bound`, StorageClass `auto-ebs-sc` |
| `kubectl get nodes -L eks.amazonaws.com/compute-type` | Value `auto` |

## 🧹 Cleanup
```bash
kubectl delete -f manifests/ --ignore-not-found       # NLB and EBS volume are removed by Auto Mode
(cd ../../02-create-eks-cluster && ./scripts/down.sh --cluster-name=eksauto)
```

## 📝 Notes & cost
- Auto Mode charges a **management fee per EC2 instance-hour on top of the EC2 price**. Spot, Savings Plans and Reserved Instances reduce the EC2 part but not the fee. Current numbers: https://aws.amazon.com/eks/pricing/.
- Auto Mode does not create a default StorageClass. Create one that uses `ebs.csi.eks.amazonaws.com`.
- Auto Mode nodes are in the private subnets, so the cluster has one NAT gateway (billed per hour and per GB).
