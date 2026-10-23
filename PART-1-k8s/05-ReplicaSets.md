# ReplicaSets

**Learning objective:** use a ReplicaSet to keep N Pods alive and see self-healing.

## Demo

1. "Apply a ReplicaSet asking for 3 nginx Pods."
   ```bash
   kubectl apply -f 00-manifests/web-rs.yaml
   kubectl get rs,pods -l app=web
   ```
   Expected: `web-rs` DESIRED 3 / CURRENT 3 / READY 3; three Pods.

2. "Now the magic — delete one Pod."
   ```bash
   kubectl delete pod -l app=web --field-selector=status.phase=Running | head -1
   kubectl get pods -l app=web
   ```
   Expected: briefly 2, then back to 3 — a new Pod with a new name appears.

3. "Who owns these Pods? The ReplicaSet, via ownerReferences."
   ```bash
   kubectl get pod -l app=web -o jsonpath='{.items[0].metadata.ownerReferences[0].kind}'; echo
   ```
   Expected: `ReplicaSet`.

4. "Clean up — note this also deletes the Pods it owns."
   ```bash
   kubectl delete -f 00-manifests/web-rs.yaml
   ```

**Conclusions:**

- ReplicaSet = replicas + selector + template.
- Delete an owned Pod and it's recreated — self-healing in action.
- But ReplicaSets can't do rolling updates. That's why we use Deployments next.