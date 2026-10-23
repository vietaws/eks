# 03 — Classic Load Balancer (CLB)

## 🎯 Scenario
Expose a Deployment to the internet using a Kubernetes `Service` of
`type: LoadBalancer`. With no extra annotation, EKS provisions a **Classic Load
Balancer (CLB)** via the legacy in-tree cloud provider.

> ⚠️ **CLB is legacy.** AWS recommends NLB (L4) or ALB (L7) for all new work.
> This demo exists only to show the default behavior and *why* you should move on. See `04-nlb` and `06-alb` for the modern path.

## 🗺️ Architecture
```
Internet → Classic LB (ELB) → NodePort → Pods (home-app, :8080)
```

## ✅ Prerequisites
- EKS cluster with a worker node group in public subnets (see `02-create-eks-cluster`).
- `kubectl` pointing at the cluster.

## 🚀 Steps
```bash
# Deploy the app + Service type LoadBalancer (CLB)
kubectl apply -f ./manifests
```

## 🔍 Validation
```bash
# Wait for the EXTERNAL-IP (an *.elb.amazonaws.com hostname) to appear
kubectl get svc clb-demo -w

# Test it
curl http://<EXTERNAL-IP>
```

## 🧹 Cleanup
```bash
kubectl delete -f ./manifests
# Confirm the ELB is gone (it bills per hour):
aws elb describe-load-balancers --profile eks --region ap-southeast-1
```

## 📝 Notes & cost
- A CLB bills ~per hour + per GB — **delete it when done**.
- Modern replacement: a `Service` with `loadBalancerClass: service.k8s.aws/nlb`
  (managed by the AWS Load Balancer Controller) gives you an NLB with target-group
  health checks and IP targeting. CLB cannot do target-type `ip`.
