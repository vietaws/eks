# Benefits

- Upgrade worker nodes automatically by using Karpenter

An eksctl-managed cluster can be upgraded in 3 easy steps:

- upgrade control plane version with eksctl upgrade cluster

- replace each of the nodegroups by creating a new one and deleting the old one

- update default add-ons (more about this here):

  kube-proxy

  aws-node

  coredns

# Verify

```
# Nodepool
kubectl get nodepool

# NodeClass
kubectl get ec2nodeclass

# Run a deployment
kubectl apply -f manifests/app.yaml

# Scale more replicas
kubectl scale deployment inflate --replicas 3
```

# Upgrade kubectl

```
📗 https://docs.aws.amazon.com/eks/latest/userguide/install-kubectl.html

# Check before start
kubectl version

// Output
Client Version: v1.29.4
Kustomize Version: v5.0.4-0.20230601165947-6ce0bf390ce3
Server Version: v1.29.4-eks-036c24b

# Download v1.30
curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.30.0/2024-05-12/bin/darwin/amd64/kubectl

# Download v1.29
curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.29.3/2024-04-19/bin/darwin/amd64/kubectl


# Chmod
chmod +x ./kubectl

# Install
mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$HOME/bin:$PATH

# Verify
kubectl version

// Output
Client Version: v1.30.0-eks-036c24b
Kustomize Version: v5.0.4-0.20230601165947-6ce0bf390ce3
Server Version: v1.29.4-eks-036c24b
```

# Upgrade cluster

```
# Check version
eksctl version

# Check eksctl EKS version support
https://github.com/eksctl-io/eksctl/releases

# Install / Upgrade guide
https://eksctl.io/installation/

// ARCH=arm64 # MacOS Apple M1


# Verify
eksctl version
0.181.0

# Command
eksctl upgrade cluster --name karpenter3 --version=1.30 --approve --profile default

🚨 Error: control plane version "1.30" is not known to this version of eksctl, try to upgrade eksctl first

🚀 You have to upgrade kubectl version first!!!

// Output

✅ 2024-06-06 17:10:58 [ℹ]  will upgrade cluster "karpenter4" control plane from current version "1.29" to "1.30"

⏰ You will wait around 10 minutes for ugprading completed!
```

# Upgrade worker node

```
# Check EC2 worker Spot node AMI
kubectl describe ec2nodeclass default

Spec:
  Ami Family:  AL2
  Metadata Options:
    Http Endpoint:                enabled
    httpProtocolIPv6:             disabled
    Http Put Response Hop Limit:  2
    Http Tokens:                  required
  Role:                           KarpenterNodeRole-karpenter3
  Security Group Selector Terms:
    Tags:
      karpenter.sh/discovery:  karpenter3
  Subnet Selector Terms:
    Tags:
      karpenter.sh/discovery:  karpenter3
Status:
  Amis:
    Id:    ami-02045a893de34d57c
    Name:  amazon-eks-arm64-node-1.29-v20240531

📗 https://aws.amazon.com/blogs/containers/how-to-upgrade-amazon-eks-worker-nodes-with-karpenter-drift/

By default, karpenter drift interval is set to 5 mintues. However, if the NodePool or EC2NodeClass is updated, then the Drift check is triggered immediately. In EC2NodeClass, amiFamily is a required field, and you can use your own AMI value, or EKS Optimized AMIs. Drift for AMIs has two behaviors in these two cases which are detailed below.

# Monitor Nodes
kubectl get nodes -w

# Monitor Nodes
eks-node-viewer

# Edit ec2nodeclass to remove specified AMI
kubectl edit ec2nodeclass default

=> Remove AMI Specified selector (02 rows)

// Output
4 nodes (7650m/19680m) 38.9% cpu ████████████████░░░░░░░░░░░░░░░░░░░░░░░░ $0.468/hour | $341.494/month
18 pods (0 pending 18 running 18 bound)

ip-192-168-58-185.ap-southeast-1.compute.internal  cpu ███████████████████████░░░░░░░░░░░░  65% (5 pods) t3.medium/$0.0528  On-Demand -        Ready
ip-192-168-27-29.ap-southeast-1.compute.internal   cpu ███████████████████████░░░░░░░░░░░░  65% (5 pods) t3.medium/$0.0528  On-Demand -        Ready
ip-192-168-109-229.ap-southeast-1.compute.internal cpu ███████████████████████░░░░░░░░░░░░  65% (8 pods) c4.2xlarge/$0.1811 Spot      Cordoned Ready
i-0f5f85827529653cb                                cpu ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   0% (0 pods) c4.2xlarge/$0.1811 Spot      -        NotReady/12s
```

# Clean

```
# Delete deployment
kubectl delete deployment inflate
```
