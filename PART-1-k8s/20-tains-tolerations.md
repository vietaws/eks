# Taints & Tolerations

**Learning objective:** repel Pods from a node with a taint, and admit specific ones with a toleration.

"nodeSelector *attracts* Pods to nodes. Taints do the opposite — they *repel* Pods, unless a Pod explicitly tolerates the taint. It's how you reserve nodes for special workloads. Let's taint a node and watch Pods avoid it."

## Demo

1. "Imperative first — taint worker2 so normal Pods avoid it."
   ```bash
   kubectl taint node k8s-course-worker2 dedicated=batch:NoSchedule
   kubectl describe node k8s-course-worker2 | grep -i taint
   ```
   Expected: `dedicated=batch:NoSchedule` listed.

2. "A Pod with a matching toleration CAN land there."
   ```bash
   kubectl apply -f 00-manifests/batch-pod.yaml
   kubectl get pod batch-pod -o wide
   ```
   Expected: `batch-pod` may schedule onto worker2 (it tolerates the taint).

3. "A Pod WITHOUT a toleration, forced to worker2, stays Pending."
   ```bash
   kubectl run notol --image=nginx:1.27-alpine \
     --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"k8s-course-worker2"}}}'
   sleep 3
   kubectl get pod notol        # Pending (taint not tolerated)
   kubectl delete pod notol --force --grace-period=0
   ```
   Expected: `Pending`, `Unschedulable`.

4. "Remove the taint (trailing dash)."
   ```bash
   kubectl taint node k8s-course-worker2 dedicated-
   kubectl delete -f 00-manifests/batch-pod.yaml
   ```

**✅ Conclusions:**

- Taint = repel; effects NoSchedule / PreferNoSchedule / NoExecute.
- Toleration on a Pod lets it ignore a matching taint.
- Control-plane nodes are tainted by default — that's why your Pods avoid them.
- Next: node affinity for richer attract-rules.