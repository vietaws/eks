# 23 — EBS CSI Driver & Dynamic Provisioning

## 🎯 Scenario
Use the **Amazon EBS CSI driver** to dynamically provision block storage (`PersistentVolume`) for stateful pods, then explore resizing, volume types (gp3, io2, io2 Block Express), topology, StatefulSets, and static provisioning.

## 🗺️ Sub-demos
| Folder | Teaches |
|--------|---------|
| `01-basics` | Install EBS CSI driver (IRSA/Pod Identity), dynamic PVC |
| `02-resize` | Online volume expansion |
| `03-params` | StorageClass parameters (type, iops, throughput, encryption) |
| `04-using-io2` / `05-using-io2-express` | High-performance volume types |
| `06-topo` | Topology-aware scheduling (AZ pinning) |
| `07-multiple-pods` | Access-mode behavior with multiple pods |
| `08-statefulsets` | `volumeClaimTemplates` (one PV per replica) |
| `09-static-provisioning` | Pre-created EBS volume → PV |

## ✅ Prerequisites
- EKS cluster with worker nodes.
- IAM: `AmazonEBSCSIDriverPolicy` (AWS managed) attached to the driver role.
- `kubectl`.

## 🚀 Steps
```bash
# Install the driver as a managed add-on (recommended)
aws eks create-addon --cluster-name eksdemo --addon-name aws-ebs-csi-driver \
  --service-account-role-arn arn:aws:iam::ACCOUNT_ID:role/AmazonEKS_EBS_CSI_DriverRole --profile eks

# Then work through 01-basics → 09-static-provisioning
kubectl apply -f 01-basics/manifests
```

## 🔍 Validation
```bash
kubectl get csidriver ebs.csi.aws.com
kubectl get sc,pvc,pv
kubectl exec -it app -- cat /data/out.txt
```

## 🧹 Cleanup
```bash
kubectl delete -f 01-basics/manifests
# Deleting a PVC with a Delete reclaim policy also deletes the EBS volume.
kubectl get pv   # confirm nothing is left billing
```

## 📝 Notes & cost
- 🔐 **Use the AWS managed `AmazonEBSCSIDriverPolicy`** instead of the inline `Resource: "*"` policy shown in some tutorials — it's scoped and maintained.
- Prefer **gp3** over gp2 (cheaper, configurable IOPS/throughput).
- Use **EKS Pod Identity** instead of IRSA for the driver's service account.
- EBS volumes bill while they exist — a `Delete` reclaim policy cleans them up with the PVC; `Retain` leaves them (and the bill) behind.
