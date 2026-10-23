# 17 — Fargate Profile Basics

## 🎯 Scenario
Run pods on **AWS Fargate** (serverless, no EC2 nodes to manage). A Fargate **profile** tells EKS which namespace/label selectors should land on Fargate.

## 🗺️ Architecture
```
Fargate profile (selector: namespace=fargate-ns)
  → pods in that namespace run on Fargate microVMs
  → ALB with target-type: ip (required for Fargate)
```

## ✅ Prerequisites
- EKS cluster.
- AWS Load Balancer Controller (`06-alb`) — Fargate needs `target-type: ip`.
- `eksctl`.

## 🚀 Steps
```bash
# 1. Create the Fargate profile (replace cluster name)
eksctl create fargateprofile \
  --cluster vietvn \
  --name fp \
  --namespace fargate-ns \
  --profile eks

# 2. Deploy the app + Ingress into that namespace
kubectl apply -f ./manifests
```

## 🔍 Validation
```bash
# Nodes show "fargate-..." as the node name for these pods
kubectl get pods -n fargate-ns -o wide
kubectl get nodes | grep fargate
```

## 🧹 Cleanup
```bash
kubectl delete -f ./manifests
eksctl delete fargateprofile --cluster eksdemo --name fp --profile eks
```

## 📝 Notes & cost
- Fargate requires `alb.ingress.kubernetes.io/target-type: ip` — there are no nodes to register in `instance` mode.
- Fargate bills per-pod vCPU/GB per second. For small, bursty demo workloads it can be cheaper than keeping an EC2 node running; for steady workloads a Spot node group is usually cheaper.
- Fargate pods can't use DaemonSets, privileged containers, or host networking.
