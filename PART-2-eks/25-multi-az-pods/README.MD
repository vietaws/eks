# 25 — Multi-AZ Persistent Volume Scheduling

## 🎯 Scenario
EBS volumes are **zonal** — a pod can only mount an EBS PV in the same AZ. This demo shows how `volumeBindingMode: WaitForFirstConsumer` lets the scheduler place the pod first, then provision the EBS volume in the **right AZ**.

## 🗺️ Architecture
```
StorageClass (WaitForFirstConsumer) → scheduler picks node/AZ for the pod
                                     → EBS volume created in that same AZ
```

## ✅ Prerequisites
- EBS CSI driver installed (`23-ebs/01-basics`).
- Node group spanning multiple AZs.

## 🚀 Steps
```bash
kubectl apply -f manifest
```

## 🔍 Validation
```bash
kubectl get nodes -o wide          # note the AZ labels
kubectl get pvc,pv
kubectl get pod -o wide            # pod + its PV land in the same AZ
```

## 🧹 Cleanup
```bash
kubectl delete -f manifest
kubectl get pv    # confirm EBS volumes are gone
```

## 📝 Notes & cost
- A Deployment sharing one PVC always gets **one** PV (shared), regardless of `accessModes`. For a PV **per replica**, use a StatefulSet with `volumeClaimTemplates` (see `23-ebs/08-statefulsets`).
- `WaitForFirstConsumer` is the key setting that avoids "volume node affinity conflict" errors in multi-AZ clusters.
- Cross-AZ pod↔volume is impossible for EBS; use **EFS** (`26-efs`) if you need shared, multi-AZ, ReadWriteMany storage.
