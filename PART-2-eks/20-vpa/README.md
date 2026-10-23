# 20 — Vertical Pod Autoscaler (VPA)

## 🎯 Scenario
Right-size pods automatically by adjusting their **CPU/memory requests** based on observed usage. Where HPA adds *more* pods, VPA makes each pod the *right size* —
useful for cost savings and for workloads that don't scale horizontally.

## 🗺️ Architecture
```
metrics-server → VPA Recommender (reads history)
              → VPA Updater (evicts under/over-sized pods)
              → VPA Admission webhook (injects new requests on recreate)
```

## ✅ Prerequisites
- metrics-server installed (see `19-hpa`).
- `git`, `kubectl`.

## 🚀 Steps
```bash
# 1. Install VPA from the autoscaler repo
git clone https://github.com/kubernetes/autoscaler.git
cd autoscaler/vertical-pod-autoscaler/
./hack/vpa-up.sh
kubectl get pods -n kube-system | grep vpa

# 2. Deploy demo app + VPA object
kubectl apply -f 01-vpa-app.yaml
kubectl apply -f 02-vpa-configure.yaml
```

## 🔍 Validation
```bash
kubectl get vpa
kubectl describe vpa vpa-vietaws     # see the CPU/memory recommendation
```

## 🧹 Cleanup
```bash
kubectl delete -f 02-vpa-configure.yaml -f 01-vpa-app.yaml
# Optional: remove VPA components
# (cd autoscaler/vertical-pod-autoscaler && ./hack/vpa-down.sh)
```

## 📝 Notes & cost
- VPA **evicts** pods to resize them, so keep ≥2 replicas for availability; a single-replica Deployment won't be resized until you delete its pod.
- Do **not** run VPA in `Auto` mode on the same workload as HPA on CPU/memory — they fight. Use VPA in `Off`/recommendation mode alongside HPA, or VPA for requests + HPA on custom metrics.
- Pure cost-optimization feature; no direct AWS charge.
