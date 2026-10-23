# 19 — Horizontal Pod Autoscaler (HPA)

## 🎯 Scenario
Scale the **number of pods** up and down automatically based on CPU utilization.
HPA is built into Kubernetes; it only needs the metrics-server.

## 🗺️ Architecture
```
metrics-server → HPA controller → adjusts Deployment replicas (1..10)
```

## ✅ Prerequisites
- EKS cluster with worker nodes (HPA does not add nodes — see `21`/`22` for that).
- `kubectl`.

## 🚀 Steps
```bash
# 1. Install metrics-server (use the latest release tag)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl -n kube-system get deploy metrics-server

# 2. Deploy the demo app (requests/limits are set so HPA has a baseline)
kubectl apply -f 01-hpa-demo.yaml

# 3. Create the HPA
kubectl autoscale deployment hpa-demo-deployment --cpu-percent=50 --min=1 --max=10
```

## 🔍 Validation
```bash
# Generate load (run in a second terminal)
kubectl run test-load --rm -it --restart=Never --image=busybox -- \
  /bin/sh -c "while true; do wget -q -O- http://hpa-demo-service; done"

# Watch replicas climb
kubectl get hpa hpa-demo-deployment -w
kubectl get pods -w
```

## 🧹 Cleanup
```bash
kubectl delete hpa hpa-demo-deployment
kubectl delete -f 01-hpa-demo.yaml
```

## 📝 Notes & cost
- Default scale-down stabilization is ~5 min, so pods shrink gradually.
- Modern alternative to the imperative `kubectl autoscale`: commit a `HorizontalPodAutoscaler` (`autoscaling/v2`) manifest with multiple metrics.
- HPA adds **pods**, not nodes. Pair it with Karpenter (`22`) so new pods that can't fit trigger new nodes.
- No extra AWS cost unless pod growth forces new nodes.
