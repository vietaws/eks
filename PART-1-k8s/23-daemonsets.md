# DaemonSets

**Learning objective:** run exactly one Pod per node with a DaemonSet.

"Some things must run on *every* node — a log collector, a metrics agent, a network plugin. Not '3 replicas somewhere' but 'one on each node.' That's a DaemonSet."

## Demo

1. "Apply a DaemonSet — a tiny per-node agent."
   ```bash
   cat 00-manifests/node-agent.yaml
   kubectl apply -f 00-manifests/node-agent.yaml
   kubectl rollout status ds/node-agent
   ```
   Expected: DaemonSet rolls out.

2. "One Pod per worker (control-plane is tainted, so skipped)."
   ```bash
   kubectl get ds node-agent
   kubectl get pods -l app=node-agent -o wide
   ```
   Expected: DESIRED 2 / READY 2; one Pod on each worker.

3. "Each Pod knows its node (via the downward API)."
   ```bash
   kubectl logs -l app=node-agent --prefix | sort -u
   ```
   Expected: `agent on k8s-course-worker` and `... worker2`.

4. "Clean up."
   ```bash
   kubectl delete -f 00-manifests/node-agent.yaml
   ```

**✅ Conclusions:**

- DaemonSet = one Pod per eligible node (no replica count).
- Auto-adjusts as nodes join/leave.
- Skips tainted nodes unless tolerated.

## Real World DaemonSets Use Case

**Learning objective:** recognize when a workload should be a DaemonSet.

"You've already been running DaemonSets this whole course without noticing.
Let's look at the real ones in your cluster and the pattern they share."

1. "Your cluster already runs DaemonSets — look at kube-system."
   ```bash
   kubectl get ds -n kube-system
   ```
   Expected: `kube-proxy` and `kindnet` (the CNI), one Pod per node each.

2. "Confirm kindnet is one-per-node."
   ```bash
   kubectl get pods -n kube-system -l app=kindnet -o wide
   ```
   Expected: one kindnet Pod on every node, including control-plane (it tolerates
   the taint — that's lesson 8).

3. "Compare: a Deployment scales with load; a DaemonSet scales with nodes."

**✅ Conclusions:**

- DaemonSet = per-node work: logging, metrics, storage, networking.
- kube-proxy and the CNI are DaemonSets in every cluster.
- Rule of thumb: scales with nodes → DaemonSet.