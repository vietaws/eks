# 11 — Auto-Assign a Custom Domain (ExternalDNS)

## 🎯 Scenario
Let **ExternalDNS** automatically create a Route 53 record for the ALB, so your Ingress is reachable at a friendly hostname without manually editing DNS.

## 🗺️ Architecture
```
Ingress (external-dns.alpha.kubernetes.io/hostname: demo.<your-domain>)
  → AWS LBC provisions ALB
  → ExternalDNS watches the Ingress → writes Route 53 A/ALIAS record
```

## ✅ Prerequisites
- AWS Load Balancer Controller installed (`06-alb`).
- ExternalDNS installed with Route 53 permissions (`10-route53`).
- A Route 53 **public hosted zone** for your domain.
- ACM certificate for the domain.

## 🚀 Steps
1. Edit `manifests/05-alb.yaml`:
   - set your ACM cert ARN (`ACCOUNT_ID`/`CERT_ID` placeholders),
   - set `external-dns.alpha.kubernetes.io/hostname` to **your** domain.
2. Apply:
   ```bash
   kubectl apply -R -f ./manifests
   ```

## 🔍 Validation
```bash
kubectl get ingress
# Wait ~1-3 min for ExternalDNS to sync, then:
dig +short demo.<your-domain>
curl https://demo.<your-domain>/app1
```

## 🧹 Cleanup
```bash
kubectl delete -R -f ./manifests
# ExternalDNS removes the Route 53 record when the Ingress is deleted
```

## 📝 Notes & cost
- ExternalDNS polls every ~1 min by default; records are created/removed with the Ingress lifecycle.
- 🔐 Keep real domain, account ID, and cert ARN out of committed manifests.
- Route 53 hosted zone bills ~$0.50/mo + per-query; ALB bills per hour.
