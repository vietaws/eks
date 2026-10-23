# 07 — ALB Path-Based Routing

## 🎯 Scenario
Use a single ALB to route by **URL path**: `/app1` → app1, `/app2` → app2, and
`/` → the home app. One load balancer, three backends.

## 🗺️ Architecture
```
ALB ── /app1 → app1-svc → app1 pods
    ├─ /app2 → app2-svc → app2 pods
    └─ /     → home-svc → home pods
```

## ✅ Prerequisites
- AWS Load Balancer Controller installed (`06-alb`).
- Default `aws-ingress-class` IngressClass present.

## 🚀 Steps
```bash
kubectl apply -f ./manifests
```

## 🔍 Validation
```bash
kubectl get ingress vietvn-ingress-cpr-demo -w   # wait for ADDRESS
ALB=$(kubectl get ingress vietvn-ingress-cpr-demo -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl http://$ALB/app1
curl http://$ALB/app2
curl http://$ALB/
```

## 🧹 Cleanup
```bash
kubectl delete -f ./manifests
```

## 📝 Notes & cost
- **Order matters:** keep the `/` (root) rule **last**, otherwise it shadows the more specific paths.
- Uses `spec.ingressClassName` (modern) — the deprecated
  `kubernetes.io/ingress.class` annotation is intentionally left out.
- One ALB for all three paths keeps cost down vs. one ALB per app.
