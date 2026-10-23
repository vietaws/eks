# 16 — Internal ALB

## 🎯 Scenario
Create an **internal** Application Load Balancer (private IPs only), reachable from inside the VPC but not the internet. Used for internal web apps/APIs.

## 🗺️ Architecture
```
curl-pod (in-cluster) → Internal ALB (private subnets) → Pods (app1/app2/home)
```

## ✅ Prerequisites
- AWS Load Balancer Controller installed (`06-alb`).
- Private subnets tagged `kubernetes.io/role/internal-elb = 1`.

## 🚀 Steps
```bash
kubectl apply -f ./manifests
```
Key annotation in `05-alb.yaml`:
```yaml
alb.ingress.kubernetes.io/scheme: internal
```

## 🔍 Validation
An internal ALB has no public DNS — test from the in-cluster `curl-pod`:
```bash
kubectl get ingress vietvn-ingress-internal-lb-demo
kubectl exec -it curl-pod -- curl http://<internal-alb-dns>/app1
```

## 🧹 Cleanup
```bash
kubectl delete -f ./manifests
```

## 📝 Notes & cost
- The only functional difference from a public ALB is `scheme: internal` plus the subnet tag — same controller, same Ingress API.
- An internal ALB still bills per hour + LCU — delete when done.
