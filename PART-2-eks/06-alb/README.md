# 06 — Install the AWS Load Balancer Controller (ALB)

## 🎯 Scenario
Install the **AWS Load Balancer Controller (LBC)** and provision your first
Application Load Balancer via a Kubernetes `Ingress`. Every demo from here to
`16-internal-alb` depends on this controller.

> Full install commands are in [`01-install-controller.md`](./01-install-controller.md).

## 🗺️ Architecture
```
Ingress (IngressClass: aws-ingress-class)
        → AWS Load Balancer Controller (in kube-system)
        → Application Load Balancer (L7)
        → target group → Pods (home-app, :8080)
```

## ✅ Prerequisites
- EKS cluster with IAM OIDC provider enabled (or EKS Pod Identity — see Notes).
- `helm`, `eksctl`, `kubectl`.
- Worker nodes in subnets tagged for the LBC
  (`kubernetes.io/role/elb` = 1 for public, `/internal-elb` = 1 for private).

## 🚀 Steps
```bash
# 1. IAM policy for the controller
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json --profile eks

# 2. IRSA service account (replace ACCOUNT_ID and cluster name)
eksctl create iamserviceaccount \
  --cluster=eksdemo --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn=arn:aws:iam::ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts --approve --profile eks

# 3. Install via Helm
helm repo add eks https://aws.github.io/eks-charts && helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=eksdemo \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

# 4. Default IngressClass + sample Ingress
kubectl apply -f ./manifests
```

## 🔍 Validation
```bash
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl get ingress
# Open the ALB DNS name once ADDRESS is populated
```

## 🧹 Cleanup
```bash
kubectl delete -f ./manifests
helm delete aws-load-balancer-controller -n kube-system
```

## 📝 Notes & cost
- **Modern auth:** prefer **EKS Pod Identity** over IRSA — no OIDC trust-policy
  juggling. Create a Pod Identity association for the `aws-load-balancer-controller`
  service account instead of `eksctl create iamserviceaccount`.
- `kubernetes.io/ingress.class` annotation is **deprecated** — use `spec.ingressClassName` (the manifests here already do).
- An ALB bills per hour + per LCU — delete Ingresses you are not using.
