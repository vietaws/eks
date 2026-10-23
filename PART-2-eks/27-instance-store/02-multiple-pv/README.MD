# 27.02 — One PV Per NVMe Instance-Store Disk

## 🎯 Scenario
Provision a dedicated `PersistentVolume` for **each** local NVMe disk on a node, so pods can bind to individual high-performance ephemeral disks.

> 💸 **Cost warning:** this demo needs an instance with **≥2** local NVMe disks.
> Use `i3.4xlarge` (2 disks) instead of `i3.8xlarge` (4 disks) to roughly halve the bill, and delete the node group as soon as you're done.

## 🗺️ Architecture
```
i3.4xlarge → 2 NVMe disks mounted under /mnt/fast-disks/<uuid>
           → Local Volume Static Provisioner → 2 PVs (StorageClass: fast-disks)
```

## ✅ Prerequisites
- Local Volume Static Provisioner installed (`01-configure`).
- `ng.yaml` edited with your cluster name/region.

## 🚀 Steps
```bash
# 1. Create the instance-store node group (pre-bootstrap mounts each NVMe disk)
eksctl create nodegroup -f ng.yaml --profile eks

# 2. Pin the demo app to that node and create the PVC
#    Edit manifests/02-app.yaml -> spec.nodeName (from: kubectl get nodes)
kubectl apply -f manifests
```

## 🔍 Validation
```bash
kubectl get pv                         # one PV per NVMe disk
kubectl get pvc
kubectl exec -it <app-pod> -- df -BG | grep fast-disks
```

## 🧹 Cleanup
```bash
kubectl delete -f manifests
kubectl delete pv --all                # local PVs are Retain by default
eksctl delete nodegroup --cluster eksdemo --name eks-pv-nvme-ng --profile eks
```

## 📝 Notes & cost
- Each disk becomes its own PV — contrast with RAID-0 (`03`) which stripes all disks into **one** large PV.
- Instance store is **ephemeral**; terminating the node destroys the data.
- The large EC2 instance is the whole cost here — tear it down promptly.
