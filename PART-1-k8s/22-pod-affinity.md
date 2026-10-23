# Pod Affinity / Anti-Affinity

**Learning objective:** place Pods relative to other Pods (co-locate or spread).

"Sometimes placement depends on *other Pods*, not nodes. 'Keep my replicas on separate nodes for resilience' or 'put the cache next to the app.' That's pod affinity and anti-affinity."

## Demo

1. "This Deployment uses anti-affinity on its own label — spread one per node."
   ```bash
   cat 00-manifests/spread-web.yaml
   kubectl apply -f 00-manifests/spread-web.yaml
   kubectl rollout status deploy/spread-web
   ```
   Expected: 2 replicas become ready.

2. "Confirm they're on different nodes."
   ```bash
   kubectl get pods -l app=spread-web -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort -u
   ```
   Expected: two distinct worker nodes.

3. "Scale to 3 — with only 2 workers, the 3rd can't satisfy 'required' anti-affinity."
   ```bash
   kubectl scale deploy/spread-web --replicas=3
   sleep 4
   kubectl get pods -l app=spread-web -o wide
   ```
   Expected: 2 Running, 1 Pending (no third node without a same-app Pod).

4. "Clean up."
   ```bash
   kubectl delete -f 00-manifests/spread-web.yaml
   ```

**✅ Conclusions:**

- Pod affinity/anti-affinity place Pods relative to other Pods.
- `topologyKey` sets the domain (hostname = per node).
- `required` anti-affinity can leave Pods Pending if topology runs out.
- Next: DaemonSets — exactly one Pod per node by design.