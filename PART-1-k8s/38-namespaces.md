# Namespaces & Resource Quotas

**Learning objective:** partition a cluster with namespaces and cap usage with a ResourceQuota.

"One cluster, many teams or environments. How do you keep them from stepping on each other — or hogging all the CPU? Namespaces partition; ResourceQuotas cap."

## Demo

1. "Imperative first — create a namespace."
   ```bash
   kubectl create namespace course-demo
   kubectl get ns course-demo
   ```
   Expected: `course-demo` Active.

2. "Apply a quota: at most 2 Pods, limited CPU/memory."
   ```bash
   cat 00-manifests/quota.yaml
   kubectl apply -f 00-manifests/quota.yaml
   kubectl describe resourcequota demo-quota -n course-demo
   ```
   Expected: hard limits listed (pods=2, cpu, memory).

3. "Exceed it — the 3rd Pod is rejected by the quota."
   ```bash
   kubectl -n course-demo create deployment web --image=nginx:1.27-alpine --replicas=3
   sleep 3
   kubectl -n course-demo get deploy web          # fewer than 3 available
   kubectl -n course-demo get events | grep -i quota | tail -1
   ```
   Expected: quota blocks Pods beyond the cap (forbidden: exceeded quota).

4. "Clean up the whole namespace in one shot."
   ```bash
   kubectl delete namespace course-demo
   ```

**✅ Conclusions:**

- Namespace = virtual cluster; delete it to clean everything inside.
- ResourceQuota caps aggregate usage + object counts per namespace.
- Next: ServiceAccounts — identity for workloads.