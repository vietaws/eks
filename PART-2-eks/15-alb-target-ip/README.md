# 15 — ALB Target-Type `ip`

## 🎯 Scenario
Register **pod IPs directly** in the ALB target group (`target-type: ip`) instead of routing through a NodePort (`target-type: instance`). This removes the extra
node hop and is **required for Fargate** (no nodes to register).

## 🗺️ Architecture
```
instance mode:  ALB → NodePort → kube-proxy → Pod   (extra hop)
ip mode:        ALB → Pod IP directly                (this demo)
```

## ✅ Prerequisites
- AWS Load Balancer Controller installed (`06-alb`).
- VPC CNI (pods get VPC-routable IPs — default on EKS).

## 🚀 Steps
1. Edit `manifests/05-alb.yaml`: set your cert ARN and domain placeholders.
   The key annotation:
   ```yaml
   alb.ingress.kubernetes.io/target-type: ip
   ```
2. Apply:
   ```bash
   kubectl apply -f ./manifests
   ```

## 🔍 Validation
```bash
kubectl get ingress vietvn-alb-target-ip -w
# In the EC2 console, the ALB target group lists POD IPs, not instance IDs
curl https://<alb-dns-or-domain>/app1
```

## 🧹 Cleanup
```bash
kubectl delete -f ./manifests
```

## 📝 Notes & cost
- `ip` mode is the modern default for most workloads and the only option on Fargate.
- Health checks hit the pod directly, so draining/rollouts are smoother.
- 🔐 Replace cert ARN / domain placeholders with your own.
