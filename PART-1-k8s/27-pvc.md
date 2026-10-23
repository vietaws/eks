# PersistentVolumeClaims

**Learning objective:** claim storage with a PVC and prove data survives a Pod restart.

"You don't provision disks by hand in Kubernetes — you *claim* storage and let the cluster provide it. Let's claim a volume, write to it, destroy the Pod, and watch the data survive."

## Demo

1. "Create the PVC and a Pod that writes to it."
   ```bash
   cat 00-manifests/pvc-demo.yaml
   kubectl apply -f 00-manifests/pvc-demo.yaml
   kubectl wait --for=condition=Ready pod/pvc-writer --timeout=90s
   ```
   Expected: Pod Running.

2. "The PVC is Bound and a PV was auto-created."
   ```bash
   kubectl get pvc data-pvc
   kubectl get pv
   ```
   Expected: PVC `Bound`; a dynamically-provisioned PV appears.

3. "It wrote a line. Delete the Pod and recreate it."
   ```bash
   kubectl logs pvc-writer
   kubectl delete pod pvc-writer
   kubectl apply -f 00-manifests/pvc-demo.yaml
   kubectl wait --for=condition=Ready pod/pvc-writer --timeout=90s
   ```
   Expected: first run shows 1 line.

4. "Data survived — now there are TWO lines (old + new)."
   ```bash
   kubectl exec pvc-writer -- cat /data/log.txt
   ```
   Expected: two timestamped lines — persistence proven.

5. "Clean up (deleting the PVC releases the PV)."
   ```bash
   kubectl delete -f 00-manifests/pvc-demo.yaml
   ```

**✅ Conclusions:**

- PVC = a request for storage; the cluster binds/provisions a PV.
- kind auto-provisions via the default StorageClass (WaitForFirstConsumer).
- Data persists across Pod restarts. Next: StorageClasses control the "how".