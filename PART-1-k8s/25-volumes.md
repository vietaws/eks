# Volumes (emptyDir / hostPath)

**Learning objective:** use a Pod-scoped volume to share data between containers.

"A container's filesystem vanishes when it restarts. Volumes fix that — starting with the simplest, `emptyDir`: scratch space that lives as long as the Pod and is shared by its containers."

## Demo

1. "Two containers share one emptyDir — writer creates a file, reader reads it."
   ```bash
   cat 00-manifests/emptydir-demo.yaml
   kubectl apply -f 00-manifests/emptydir-demo.yaml
   kubectl wait --for=condition=Ready pod/emptydir-demo --timeout=60s
   ```
   Expected: Pod `2/2` Running.

2. "Read the file from the READER container — it sees what WRITER wrote."
   ```bash
   kubectl exec emptydir-demo -c reader -- cat /data/msg.txt
   ```
   Expected: `hello from writer` (shared volume).

3. "emptyDir is Pod-scoped — delete the Pod and the data is gone."
   ```bash
   kubectl delete pod emptydir-demo
   ```
   Expected: gone; no durable storage left behind.

**✅ Conclusions:**

- `emptyDir` = Pod-scoped scratch, shared by containers, gone with the Pod.
- `hostPath` = a node directory (use sparingly).
- For data that must outlive the Pod → PersistentVolumes.