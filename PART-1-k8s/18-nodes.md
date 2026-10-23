# Inspecting Nodes

**Learning objective:** read a node's capacity, conditions, and hosted Pods.

"When a Pod won't schedule or a node acts up, you inspect the node. `describe node` is the richest health view in Kubernetes."

## Commands

1. "The full picture for a worker."
   ```bash
   kubectl describe node k8s-course-worker | sed -n '1,40p'
   ```
   Expected: Conditions, Capacity, Allocatable, Allocated resources sections.

2. "Conditions at a glance."
   ```bash
   kubectl get node k8s-course-worker -o jsonpath='{range .status.conditions[*]}{.type}={.status} {end}'; echo
   ```
   Expected: `Ready=True` with pressure conditions `False`.

3. "Which Pods live here right now?"
   ```bash
   kubectl get pods -A --field-selector spec.nodeName=k8s-course-worker -o wide
   ```
   Expected: system Pods (kube-proxy, kindnet) at minimum.

**✅ Conclusions:**

- `describe node` = capacity + conditions + hosted Pods.
- Conditions flag memory/disk/PID pressure before things break.

## Node Labels

**Learning objective:** label nodes and observe how the scheduler spreads Pods.

"Nodes have labels too — and they're the foundation for controlling placement.
Before we get to taints and affinity next section, let's label a node and watch how the default scheduler already spreads Pods across the cluster."

1. "Imperative first — add a label to a node."
   ```bash
   kubectl label node k8s-course-worker disktype=ssd
   kubectl get nodes -L disktype,viet.vn/node-pool
   ```
   Expected: worker now shows `disktype=ssd`; both workers show node-pool=general.

2. "Deploy several replicas and see the spread."
   ```bash
   kubectl create deployment web --image=nginx:1.27-alpine --replicas=6
   kubectl rollout status deploy/web
   kubectl get pods -l app=web -o wide --no-headers | awk '{print $7}' | sort | uniq -c
   ```
   Expected: roughly 3 and 3 across the two workers.

3. "Clean up the label and Deployment."
   ```bash
   kubectl label node k8s-course-worker disktype-
   kubectl delete deployment web
   ```

**✅ Conclusions:**

- Node labels describe nodes; `kubectl label node ...` adds them.
- The default scheduler spreads replicas across nodes for resilience.
- Next: take a node out of service safely with cordon & drain.

## Cordon & Drain

**Learning objective:** safely evacuate a node for maintenance and bring it back.

"A node needs a kernel patch or a reboot. You can't just yank it — Pods would crash. Kubernetes has a graceful procedure: cordon, then drain. Let's take a
worker out of service with zero lost workloads."

1. "Spread a Deployment across both workers first."
   ```bash
   kubectl apply -f 00-manifests/cordon.yaml
   kubectl rollout status deploy/web
   kubectl get pods -l app=web -o wide --no-headers | awk '{print $7}' | sort | uniq -c
   ```
   Expected: ~3 Pods on each worker.

2. "Cordon worker 1 — no new Pods, existing ones stay."
   ```bash
   kubectl cordon k8s-course-worker
   kubectl get nodes          # worker shows SchedulingDisabled
   ```
   Expected: `k8s-course-worker ... Ready,SchedulingDisabled`.

3. "Drain it — evict Pods so they reschedule. Ignore DaemonSets (they're per-node)."
   ```bash
   kubectl drain k8s-course-worker --ignore-daemonsets --delete-emptydir-data
   kubectl rollout status deploy/web
   kubectl get pods -l app=web -o wide --no-headers | awk '{print $7}' | sort | uniq -c
   ```
   Expected: all 6 Pods now on worker2 — none lost.

4. "Maintenance done — uncordon to allow scheduling again."
   ```bash
   kubectl uncordon k8s-course-worker
   kubectl get nodes          # back to Ready
   ```
   Expected: worker is schedulable again. (Existing Pods don't move back
   automatically; new/rescheduled Pods can land there.)

5. "Clean up."
   ```bash
   kubectl delete -f 00-manifests/cordon.yaml
   ```