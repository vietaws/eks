# 13 — IngressGroup (Share One ALB Across Ingresses)

## 🎯 Scenario
Use the AWS Load Balancer Controller **IngressGroup** feature so multiple, independently-managed `Ingress` resources (app1, app2, home) share **one** ALB.
Each team owns its own Ingress; the controller merges them.

## 🗺️ Architecture
```
Ingress(app1) ┐
Ingress(app2) ├─ group.name: my-group ─▶ single shared ALB
Ingress(home) ┘
```

## ✅ Prerequisites
- AWS Load Balancer Controller installed (`06-alb`).

## 🚀 Steps
```bash
# Each app's Ingress carries alb.ingress.kubernetes.io/group.name
kubectl apply -R -f ./manifests
```

## 🔍 Validation
```bash
kubectl get ingress -A
# All three Ingresses should show the SAME ADDRESS (one ALB)
```

## 🧹 Cleanup
```bash
kubectl delete -R -f ./manifests
```

## 📝 Notes & cost
- `group.order` controls rule priority within the shared ALB.
- **Cost win:** one ALB for many Ingresses instead of one ALB each. This is the recommended pattern for multi-team clusters.
- The ALB is deleted only when the **last** Ingress in the group is removed.
