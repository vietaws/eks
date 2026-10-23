# 14 — One ALB Across Multiple Namespaces

## 🎯 Scenario
Serve applications that live in **different namespaces** through a **single** ALB, using the AWS Load Balancer Controller IngressGroup feature. Common when each team/app has its own namespace but you want to consolidate load balancers.

## 🗺️ Architecture
```
ns: app1 → Ingress ┐
ns: app2 → Ingress ├─ same group.name ─▶ one shared ALB
ns: home → Ingress ┘
```

## ✅ Prerequisites
- AWS Load Balancer Controller installed (`06-alb`).

## 🚀 Steps
```bash
# Creates namespaces, apps, and per-namespace Ingresses in the same group
kubectl apply -R -f ./manifests
```

## 🔍 Validation
```bash
kubectl get ingress -A
# Ingresses in app1/app2/home namespaces share ONE ADDRESS
```

## 🧹 Cleanup
```bash
kubectl delete -R -f ./manifests
```

## 📝 Notes & cost
- IngressGroup works **across namespaces** — the controller merges all Ingresses with the same `group.name`.
- **Cost win:** one ALB for the whole cluster instead of one per namespace.
- Reference pattern: single ALB + multiple namespaces + Fargate profiles.
