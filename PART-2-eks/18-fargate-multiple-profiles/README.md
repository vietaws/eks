# 18 — Multiple Fargate Profiles

## 🎯 Scenario
Define **several Fargate profiles** (e.g. one per app/namespace) from a single YAML file, and route them behind a shared ALB. Shows how to segment workloads onto Fargate by namespace.

## 🗺️ Architecture
```
01-fp.yaml ── profile: home-fp (ns: home)
          ├─ profile: app1-fp (ns: app1)
          └─ profile: app2-fp (ns: app2)
          → shared ALB (IngressGroup, target-type: ip)
```

## ✅ Prerequisites
- EKS cluster.
- AWS Load Balancer Controller (`06-alb`).
- `eksctl`.

## 🚀 Steps
```bash
# 1. Create all Fargate profiles from file
eksctl create fargateprofile -f 01-fp.yaml --profile eks

# 2. Deploy namespaces, apps, and ingresses
kubectl apply -R -f ./manifests
```

## 🔍 Validation
```bash
eksctl get fargateprofile --cluster eksdemo --profile eks
kubectl get pods -A -o wide | grep fargate
kubectl get ingress -A
```

## 🧹 Cleanup
```bash
kubectl delete -R -f ./manifests
eksctl delete fargateprofile --cluster eksdemo --name home-fp --profile eks
eksctl delete fargateprofile --cluster eksdemo --name app1-fp --profile eks
eksctl delete fargateprofile --cluster eksdemo --name app2-fp --profile eks
```

## 📝 Notes & cost
- A profile can match **multiple** selectors; you don't always need one profile per namespace — keep the count minimal.
- Use an IngressGroup so all apps share **one** ALB (see `13-ingress-group`).
- Delete profiles when done — they don't bill while idle, but leftover pods do.
