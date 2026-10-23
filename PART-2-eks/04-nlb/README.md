# 04 — Network Load Balancer (NLB)

## 🎯 Scenario
Expose a Deployment through an **AWS Network Load Balancer (L4)**. This demo uses the legacy in-tree annotation so you can see the classic behavior; the **Notes** section shows the modern AWS Load Balancer Controller equivalent.

## 🗺️ Architecture
```
Internet → Network LB (L4/TCP) → NodePort → Pods (home-app, :8080)
```

## ✅ Prerequisites
- EKS cluster with a public node group.
- `kubectl` configured.

## 🚀 Steps
```bash
kubectl apply -f ./manifests
```
The Service `02-nlb.yaml` uses:
```yaml
service.beta.kubernetes.io/aws-load-balancer-type: nlb   # legacy in-tree
```

## 🔍 Validation
```bash
kubectl get svc nlb-demo -w       # wait for the *.elb hostname
curl http://<EXTERNAL-IP>
```

## 🧹 Cleanup
```bash
kubectl delete -f ./manifests
aws elbv2 describe-load-balancers --profile eks --region ap-southeast-1
```

## 📝 Notes & cost
- **Modern approach (recommended):** let the AWS Load Balancer Controller manage
  the NLB instead of the in-tree provider:
  ```yaml
  spec:
    type: LoadBalancer
    loadBalancerClass: service.k8s.aws/nlb   # AWS LBC (modern)
  metadata:
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
      service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
  ```
  This gives IP-target mode, better health checks, and avoids the deprecated in-tree cloud provider path.
- NLB bills per hour + per LCU — **delete when done**.
