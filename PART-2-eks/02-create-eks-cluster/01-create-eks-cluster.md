# Create EKS Cluster

> 💡 For the newer demos (`22-karpenter`, `32-auto-mode`) use the shared scripts instead of the manual
> commands below: `./scripts/up.sh` and `./scripts/down.sh` (see `README.md` in this folder).

## 1️⃣ - Create Amazon EKS Cluster

- ☕️ It will take 10-15 minutes to create Amazon EKS Cluster Control plane. So, take a cup of coffee 😆

```
# Create Cluster
eksctl create cluster --name=vietvn \
                      --version 1.37 \
                      --region=ap-southeast-1 \
                      --zones=ap-southeast-1a,ap-southeast-1b \
                      --without-nodegroup

# Get List of clusters
eksctl get cluster

# Create Cluster using manifest & eksctl
eksctl create cluster -f 00-cluster.yaml

```

#### Enable IAM OIDC for EKS Cluster

Purpose: Enable IAM Role for Service Account on EKS cluster

```
# Syntax
eksctl utils associate-iam-oidc-provider \
    --region region-code \
    --cluster <cluter-name> \
    --approve

# Replace with region & cluster name & profile (optional)
eksctl utils associate-iam-oidc-provider \
    --region ap-southeast-1 \
    --cluster vietvn \
    --approve

# check oidc on IAM - Identity provider or
aws eks describe-cluster --name vietvn --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5

```

### create cluster with existing vpc

```
eksctl create cluster --name=vietvn \
                      --region=ap-southeast-1 \
                      #--zones=ap-southeast-1a,ap-southeast-1b \
                      --vpc-from-kops-cluster vpc-xxx \
                      --vpc-public-subnets=subnet-yyy,subnet-zzz  \
                      --without-nodegroup
```



## 2️⃣ - Create Node Group

```
# Create Public Node Group
eksctl create nodegroup --cluster=vietvn \
                       --region=ap-southeast-1 \
                       --name=vietvn-ng2 \
                       --node-type=t3.medium \
                       --nodes=2 \
                       --nodes-min=2 \
                       --nodes-max=4 \
                       --node-volume-size=20 \
                       --managed \
                       --asg-access \
                       --external-dns-access \
                       --full-ecr-access \
                       --appmesh-access \
                       --alb-ingress-access

# Create Private node group
eksctl create nodegroup --cluster=vietvn \
                        --region=ap-southeast-1 \
                        --name=vietvn-ng \
                        --node-type=t3.medium \
                        --nodes-min=2 \
                        --nodes-max=4 \
                        --node-volume-size=20 \
                        --managed \
                        --asg-access \
                        --external-dns-access \
                        --full-ecr-access \
                        --appmesh-access \
                        --alb-ingress-access \
                        --node-private-networking
# Get NodeGroups in a EKS Cluster
eksctl get nodegroup --cluster=<Cluster-Name>
eksctl get nodegroup --cluster=vietvn

# Delete Node Group - Replace nodegroup name and cluster name
eksctl delete nodegroup <NodeGroup-Name> --cluster <Cluster-Name>
eksctl delete nodegroup vietvn-ng --cluster vietvn

# Create cluster & node group

eksctl create cluster --name=vietvn \
 --region=ap-southeast-1 \
 --zones=ap-southeast-1a,ap-southeast-1b \
 --node-type=t3.medium \
 --nodes=2 \
 --nodes-min=2 \
 --nodes-max=4 \
 --node-volume-size=20 \
 --managed \
 --full-ecr-access \
 --appmesh-access \
 --asg-access \
 --external-dns-access
```

## 3️⃣ - Delete

### List EKS Clusters

eksctl get clusters

### Capture Node Group name

eksctl get nodegroup --cluster=<clusterName>

eksctl get nodegroup --cluster=vietvn

### Delete Node Group

eksctl delete nodegroup --cluster=<clusterName> --name=<nodegroupName>

eksctl delete nodegroup --cluster=vietvn --name=vietvn-ng2

### Delete Cluster

eksctl delete cluster <clusterName>

eksctl delete cluster vietvn
