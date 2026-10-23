# StorageClasses

**Learning objective:** explain how a StorageClass drives dynamic provisioning.

"Who decided our PVC got a local-path volume? The StorageClass. It's the recipe the cluster follows to create PVs on demand."

## Demo

1. "List classes — note the (default) marker."
   ```bash
   kubectl get storageclass
   ```
   Expected: `standard (default)  rancher.io/local-path`.

2. "Details: provisioner, reclaim policy, binding mode."
   ```bash
   kubectl describe storageclass standard | head -n 12
   ```
   Expected: `WaitForFirstConsumer`, reclaimPolicy `Delete`.

3. "Our earlier PVC omitted storageClassName, so it used this default."
   ```bash
   kubectl get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}'; echo
   ```
   Expected: `standard`.

**✅ Conclusions:**

- StorageClass = the provisioning recipe (provisioner + params + policy).
- PVC without `storageClassName` → the default class.
- Cloud clusters expose multiple classes (ssd, hdd). Next: StatefulSets.