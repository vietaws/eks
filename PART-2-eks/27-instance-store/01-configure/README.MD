# 27.01 — Configure Local NVMe Instance-Store Provisioner

## 🎯 Scenario
Expose an EC2 instance's **local NVMe instance-store** disks as Kubernetes `PersistentVolume`s using the Local Volume Static Provisioner. Instance store is very fast but **ephemeral** — data is lost when the instance stops/terminates.

> 💸 **Cost warning:** instance-store families (i3, i4i, etc.) are expensive.
> For learning, use the **smallest** option (e.g. `i4i.large` or `i3.large`), **not** `i3.8xlarge`. Tear the node group down immediately after the demo.

## 🗺️ Architecture
```
NVMe disks mounted at /mnt/fast-disk
  → Local Volume Static Provisioner (DaemonSet on labeled nodes)
  → one PV per detected disk (StorageClass: fast-disks)
```

## ✅ Prerequisites
- EKS cluster.
- A node group using an instance-store instance type, nodes labeled
  `fast-disk-node=pv-nvme` (or `pv-raid`), with a pre-bootstrap script that mounts
  the NVMe disks under `/mnt/fast-disk`.

## 🚀 Steps
```bash
# 1. ServiceAccount + RBAC
kubectl apply -f manifests/01-sa.yaml

# 2. Provisioner ConfigMap (where to look for mounted disks)
kubectl apply -f manifests/02-cm.yaml

# 3. DaemonSet (only schedules on labeled fast-disk nodes)
kubectl apply -f manifests/03-ds.yaml
```

## 🔍 Validation
```bash
kubectl get sa -n kube-system | grep local
kubectl get sc                      # expect: fast-disks
kubectl -n kube-system describe ds local-volume-provisioner
# PVs appear only once a labeled node with mounted NVMe disks joins
kubectl get pv
```

## 🧹 Cleanup
```bash
kubectl delete -f manifests
# CRITICAL: delete the instance-store node group so the large EC2 stops billing
eksctl delete nodegroup --cluster eksdemo --name <ng-name> --profile eks
```

## 📝 Notes & cost
- Instance store is **ephemeral**: replicate at the application layer if you need durability.
- Non-namespaced objects created here: `PV`, `ClusterRole`,
  `ClusterRoleBinding`, `StorageClass`.
- 📗 https://aws.amazon.com/blogs/containers/eks-persistent-volumes-for-instance-store/
