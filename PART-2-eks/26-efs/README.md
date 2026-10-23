# 26 — EFS CSI Driver (Shared, Multi-AZ Storage)

## 🎯 Scenario
Use the **Amazon EFS CSI driver** for `ReadWriteMany` storage that multiple pods across multiple AZs can share — something EBS (zonal, mostly RWO) cannot do.

## 🗺️ Sub-demos
| Folder | Teaches |
|--------|---------|
| `01-config` | Install EFS CSI driver (IRSA/Pod Identity), create EFS file system |
| `02-static-provisioning` | Pre-created EFS + access point → PV |
| `03-dynamic-provisioning` | StorageClass auto-creates access points per PVC |
| `04-deployment` | Multiple pods sharing one EFS volume (RWX) |
| `05-multiple-ns` | EFS across namespaces |
| `06-fargate` | EFS mounted by Fargate pods |

## ✅ Prerequisites
- EKS cluster.
- IAM: `AmazonEFSCSIDriverPolicy` (AWS managed) on the driver role.
- An EFS file system + mount targets in each node AZ, with a security group that allows NFS (2049) from the nodes.

## 🚀 Steps
```bash
# Install driver (managed add-on recommended)
aws eks create-addon --cluster-name eksdemo --addon-name aws-efs-csi-driver \
  --service-account-role-arn arn:aws:iam::ACCOUNT_ID:role/AmazonEKS_EFS_CSI_DriverRole --profile eks

# Work through 01-config → 06-fargate
```

## 🔍 Validation
```bash
kubectl get csidriver efs.csi.aws.com
kubectl get sc,pvc,pv
kubectl exec -it efs-app-1 -- tail -f /app-logs/out.txt
```

## 🧹 Cleanup
```bash
kubectl delete -f <each demo's manifests>
# Then delete the EFS file system + mount targets in the console/CLI (it bills per GB-month).
```

## 📝 Notes & cost
- 🔐 Use the AWS managed `AmazonEFSCSIDriverPolicy` and **EKS Pod Identity** rather than a hand-written IRSA trust policy with a real account/OIDC ID.
- EFS is pay-per-GB-stored (plus throughput); good for shared config/logs, not for high-IOPS databases.
- Dynamic provisioning creates an **access point** per PVC — clean up PVCs so access points don't accumulate.
