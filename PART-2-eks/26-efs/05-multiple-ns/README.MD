# Using same EFS for multiple namespace

```
## Step 1 - Create Access Point on EFS
---
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: efs-ns-sc
provisioner: efs.csi.aws.com
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: efs-pv-ns
spec:
  capacity:
    storage: 1Gi
  volumeMode: Filesystem
  accessModes:
  - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: efs-ns-sc  # <-- match this to the StorageClass name
  csi:
    driver: efs.csi.aws.com
    volumeHandle: <fs-handle-id>::<access-point-id>

# Step 2 - Create PV for same access points for both PVC

Note 1: One PV can map to Only ONE PVC
Note 2: PV is not namespace resource, PVC is namespace resource




# Step 3 - Apply
kubectl apply -f manifests


# Step 4 - Verify

kubectl get pvc -n ns1

kubectl get pvc -n ns2

kubectl get pv

kubectl get pods -n ns1

kubectl get pods -n ns2

kubectl exec -ti home-deployment-6cc7f46c88-kc9b4 -n ns1 -- tail -f /ns-logs/out.txt

kubectl exec -ti home-deployment-68446749cd-9gcrb -n ns2 -- tail -f /ns-logs/out.txt

kubectl exec -it home-deployment-85f6968ddc-69sdb -- sh

```
