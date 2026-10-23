# 12 — ALB Host-Based Routing

## 🎯 Scenario
Route by **Host header** on a single ALB: `app1.<domain>` → app1, `app2.<domain>` → app2, everything else → home. This is how you serve multiple sites/subdomains from one load balancer.

## 🗺️ Architecture
```
ALB ── Host: app1.<domain> → app1-svc
    ├─ Host: app2.<domain> → app2-svc
    └─ default              → home-svc
```

## ✅ Prerequisites
- AWS Load Balancer Controller installed (`06-alb`).
- ExternalDNS + Route 53 for the subdomains (`10-route53`).
- ACM certificate covering the subdomains.

## 🚀 Steps
1. Edit `manifests/05-alb.yaml`: set your cert ARN and replace the `app1.eks.viet.vn` / `app2.eks.viet.vn` hosts with your own domain.
2. Apply:
   ```bash
   kubectl apply -f ./manifests
   ```

## 🔍 Validation
```bash
kubectl get ingress vietvn-host-routing -w
curl https://app1.<your-domain>
curl https://app2.<your-domain>
```

## 🧹 Cleanup
```bash
kubectl delete -f ./manifests
```

## 📝 Notes & cost
- Host-based routing shares one ALB across many hostnames — cheaper than one ALB per site.
- 🔐 Replace the hardcoded `eks.viet.vn` host and any cert ARN with your own.
