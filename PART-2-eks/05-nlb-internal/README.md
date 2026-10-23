# 05 — Internal Network Load Balancer

## 🎯 Scenario
Create an **internal** NLB (private IPs only) so a service is reachable from inside the VPC but not from the internet. Common for internal APIs and service-to-service traffic.

## 🗺️ Architecture
```
curl-pod (in-cluster) → Internal NLB (private) → NodePort → Pods (home-app)
```

## ✅ Prerequisites
- EKS cluster with a node group.
- `kubectl` configured.

## 🚀 Steps
```bash
kubectl apply -f ./manifests
```
Key annotations in `02-nlb.yaml`:
```yaml
service.beta.kubernetes.io/aws-load-balancer-type: nlb        # legacy in-tree
service.beta.kubernetes.io/aws-load-balancer-internal: "true" # private only
```

## 🔍 Validation
An internal LB has no public DNS you can hit from your laptop — test from inside the cluster:

```bash
kubectl get svc nlb-internal-demo
kubectl exec -it curl-pod -- curl http://<internal-lb-hostname>
```

## 🧹 Cleanup
```bash
kubectl delete -f ./manifests
```

## 📝 Notes & cost
- **Modern approach:** use the AWS Load Balancer Controller:
  ```yaml
  spec:
    type: LoadBalancer
    loadBalancerClass: service.k8s.aws/nlb
  metadata:
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-scheme: internal
  ```
- Even internal NLBs bill per hour + LCU — delete when done.
