# Combining Taints + DaemonSet

**Learning objective:** make a DaemonSet cover tainted nodes (like the control-plane).

"A plain DaemonSet skips tainted nodes — so your log agent would miss the control-plane. For full coverage, the DaemonSet must tolerate those taints.
Let's close that gap."

## Demo

1. "Recall the plain DaemonSet covered only 2 nodes. This one tolerates all taints."
   ```bash
   grep -A2 tolerations 00-manifests/node-agent-all.yaml
   kubectl apply -f 00-manifests/node-agent-all.yaml
   kubectl rollout status ds/node-agent-all
   ```
   Expected: rolls out.

2. "Now it covers all 3 nodes, control-plane included."
   ```bash
   kubectl get ds node-agent-all
   kubectl get pods -l app=node-agent-all -o wide
   ```
   Expected: DESIRED 3; a Pod on control-plane, worker, worker2.

3. "Contrast the two DaemonSets side by side (if lesson 6's is still around)."
   ```bash
   kubectl get ds | grep node-agent
   ```
   Expected: tolerant one = 3, plain one = 2.

4. "Clean up."
   ```bash
   kubectl delete -f 00-manifests/node-agent-all.yaml
   ```

**✅ Conclusions:**

- Plain DaemonSets skip tainted nodes; add tolerations for full coverage.
- `tolerations: [{operator: Exists}]` tolerates every taint.
- That's why real monitoring agents reach the control-plane.