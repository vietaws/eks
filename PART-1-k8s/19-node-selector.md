# nodeSelector

**Learning objective:** pin a Pod to specific nodes using a node label.

"The simplest way to control placement: 'only run this on nodes labeled disktype=ssd.' That's nodeSelector — one field, exact-match, done."

## Demo

1. "Imperative first — label a node, then pin a Pod to it in one go."
   ```bash
   kubectl label node k8s-course-worker disktype=ssd
   kubectl run ssd-pod --image=nginx:1.27-alpine --overrides='{"spec":{"nodeSelector":{"disktype":"ssd"}}}'
   kubectl get pod ssd-pod -o wide
   ```
   Expected: `ssd-pod` scheduled onto `k8s-course-worker`.
   ```bash
   kubectl delete pod ssd-pod
   ```

2. "Declarative — the committable manifest."
   ```bash
   cat 00-manifests/ssd-pod.yaml
   kubectl apply -f 00-manifests/ssd-pod.yaml
   kubectl get pod ssd-pod -o wide
   ```
   Expected: pinned to the ssd-labeled node.

3. "No matching label anywhere → Pending."
   ```bash
   kubectl label node k8s-course-worker disktype-     # remove it
   kubectl delete pod ssd-pod && kubectl apply -f 00-manifests/ssd-pod.yaml
   sleep 3
   kubectl get pod ssd-pod         # Pending (no node has disktype=ssd)
   ```
   Expected: `Pending` — the requirement can't be met.

4. "Clean up (re-add the label for later lessons if you like)."
   ```bash
   kubectl delete pod ssd-pod
   ```

**✅ Conclusions:**

- `nodeSelector` = exact-match hard requirement on node labels.
- No match anywhere → Pending.
- Need OR/preferences/anti-rules? That's affinity — coming up.
- Next: taints, which repel Pods instead of attracting them.