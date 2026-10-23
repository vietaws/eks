# 10 — ExternalDNS + Route 53

## 🎯 Scenario
Install **ExternalDNS** so Kubernetes Ingress/Service hostnames are automatically published as **Route 53** records. No more hand-editing DNS when an ALB changes.

## 🗺️ Architecture
```
Ingress/Service (hostname annotation)
  → ExternalDNS (IRSA/Pod Identity → route53:ChangeResourceRecordSets)
  → Route 53 public hosted zone record
```

## ✅ Prerequisites
- EKS cluster with OIDC (IRSA) or EKS Pod Identity.
- A Route 53 **public hosted zone** for your domain.
- AWS Load Balancer Controller (`06-alb`) if driving ALBs.

## 🚀 Steps
```bash
# 1. IAM policy (AllowExternalDNSUpdates) — route53 change + list permissions
#    See the policy JSON in this README.

# 2. IRSA service account (replace cluster + policy ARN placeholders)
eksctl create iamserviceaccount \
  --name external-dns --namespace default \
  --cluster eksdemo \
  --attach-policy-arn arn:aws:iam::ACCOUNT_ID:policy/AllowExternalDNSUpdates \
  --approve --override-existing-serviceaccounts --profile eks

# 3. Deploy ExternalDNS
#    Edit manifests/01-external-dns.yaml:
#      - set eks.amazonaws.com/role-arn to YOUR role ARN (ACCOUNT_ID placeholder)
#      - pin the image to the latest external-dns release
kubectl apply -f ./manifests
```

## 🔍 Validation
```bash
kubectl get sa external-dns
kubectl logs -l app=external-dns -f        # watch it sync records
# After deploying an Ingress with a hostname annotation:
dig +short <your-host>.<your-domain>
```

## 🧹 Cleanup
```bash
kubectl delete -f ./manifests
eksctl delete iamserviceaccount --name external-dns --namespace default --cluster eksdemo --profile eks
```

## 📝 Notes & cost
- **Modern auth:** prefer **EKS Pod Identity** over IRSA.
- Pin the ExternalDNS image to a current release rather than an old tag.
- 🔐 Do **not** commit a real account ID or role ARN — use `ACCOUNT_ID`.
- Route 53 hosted zone ≈ $0.50/mo + per-query charges.
