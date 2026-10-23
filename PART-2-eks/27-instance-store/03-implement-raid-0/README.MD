# 27.03 — RAID-0 Across NVMe Instance-Store Disks

## 🎯 Scenario
Stripe **all** of a node's local NVMe disks into a single RAID-0 array, exposed as one large, very fast `PersistentVolume`. Maximizes throughput/capacity for
scratch/cache workloads.

> 💸 **Cost warning:** RAID-0 needs ≥2 local disks. `i3.4xlarge` (2 disks) is enough to demonstrate the stripe at ~half the cost of `i3.8xlarge`. Delete the node group right after.

## 🗺️ Architecture
```
i3.4xlarge → mdadm RAID-0 over 2 NVMe disks → /dev/md0 → one big PV
```

## ✅ Prerequisites
- Local Volume Static Provisioner installed (`01-configure`).
- `ng.yaml` edited with your cluster name/region.

## 🚀 Steps
```bash
# Pre-bootstrap script installs mdadm, creates /dev/md0, formats + mounts it
eksctl create nodegroup -f ng.yaml --profile eks
kubectl apply -f manifests
```

## 🔍 Validation
```bash
kubectl get pv            # a single PV sized to the sum of all striped disks
# SSM into the node:
#   cat /proc/mdstat        # shows the RAID-0 array
#   df -BG | grep md
```

## 🧹 Cleanup
```bash
kubectl delete -f manifests
kubectl delete pv --all
eksctl delete nodegroup --cluster eksdemo --name eks-pv-raid-ng --profile eks
```

## 📝 Notes & cost
- RAID-0 has **no redundancy** — losing any disk loses the array. Fine for ephemeral scratch data only.
- One big PV (this demo) vs. one PV per disk (`02`): choose based on whether your app wants a single large volume or several independent ones.
- The striped NVMe instance is the cost driver — terminate it immediately.
