# require add-on

- vpc-cni
- kube-proxy
- coredns

# Create IAM Policy on AWS

```
# download iam policy for elb controller
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

# create IAM Policy on AWS

aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam_policy.json \
    --profile eks

```

# Create IAM Service Account on EKS

```
eksctl create iamserviceaccount \
  --cluster=vietvn \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole6 \
  --attach-policy-arn=arn:aws:iam::ACCOUNTID:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --approve --profile eks

# verify
# Get IAM Service Account
eksctl  get iamserviceaccount --cluster vietvn --profile eks

# Describe Service Account alb-ingress-controller
kubectl describe sa aws-load-balancer-controller -n kube-system
```

# Deploy ALB Ingress Controller

```
# guide: https://docs.aws.amazon.com/eks/latest/userguide/lbc-helm.html

# add eks-charts repo
helm repo add eks https://aws.github.io/eks-charts

# update your local to most recent charts
helm repo update

# install aws-load-balancer-controller


helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
 -n kube-system \
 --set clusterName=vietvn \
 --set serviceAccount.create=false \
 --set serviceAccount.name=aws-load-balancer-controller

# idms v2 only
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=vietaws \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=ap-southeast-1 \
  --set vpcId=vpc-0c1a1b2c7a575769a \
  --set image.repository=602401143452.dkr.ecr.ap-southeast-1.amazonaws.com/amazon/aws-load-balancer-controller

# addon images: https://docs.aws.amazon.com/eks/latest/userguide/add-ons-images.html


# uninstall
helm delete aws-load-balancer-controller -n kube-system


# verify
kubectl get deployment -n kube-system aws-load-balancer-controller

```
