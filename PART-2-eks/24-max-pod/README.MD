# 24 — Max Pods Per Node (ENI / IP math)

## 🎯 Scenario
With the AWS VPC CNI, each pod gets a VPC IP from an ENI, so the **instance type** caps how many pods a node can run. This demo derives and verifies that limit.

## 🗺️ The formula
```
maxPods = N * (M - 1) + 2
  N = max ENIs for the instance type
  M = IPv4 addresses per ENI
# e.g. t3.small: 3 * (4 - 1) + 2 = 11
```

## ✅ Prerequisites
- EKS cluster with a known instance type node group.
- `kubectl`, `aws` CLI, `jq`.

## 🚀 Steps
```bash
# 1. Look up N and M for your instance family
aws ec2 describe-instance-types --filters "Name=instance-type,Values=t3.*" \
  --query "InstanceTypes[].{Type:InstanceType, MaxENI:NetworkInfo.MaximumNetworkInterfaces, IPv4:NetworkInfo.Ipv4AddressesPerInterface}" \
  --output table

# 2. Deploy and scale the app past the limit to see pods go Pending
kubectl apply -f manifests
kubectl scale deployments.apps app-deployment --replicas=20
```

## 🔍 Validation
```bash
# Count pods per node; some pods stay Pending once the IP limit is hit
kubectl get pod -o=custom-columns=NODE:.spec.nodeName,NAME:.metadata.name --all-namespaces \
  | grep <node-name> | wc -l
kubectl get pods -o wide | grep Pending
```

## 🧹 Cleanup
```bash
kubectl delete -f manifests
```

## 📝 Notes & cost
- To **raise** the limit without bigger instances, enable **prefix delegation** on the VPC CNI (`ENABLE_PREFIX_DELEGATION=true`), which assigns /28 prefixes and dramatically increases pods-per-node. See:
  https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html
- Nitro instances support prefix delegation; this is the modern way to pack more pods per node and lower cost per pod.
