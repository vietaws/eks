# Resource Requests & Limits

**Learning objective:** set requests/limits and understand scheduling, throttling, OOMKill, and QoS.

"Two numbers decide where your Pod runs and whether it survives under pressure: requests and limits. Get them wrong and you either waste money or get your Pod killed."

## Demo

1. "A Pod with both requests and limits set."
   ```bash
   cat 00-manifests/resources-demo.yaml
   kubectl apply -f 00-manifests/resources-demo.yaml
   kubectl wait --for=condition=Ready pod/resources-demo --timeout=60s
   ```
   Expected: Running.

2. "Its QoS class comes from requests vs limits."
   ```bash
   kubectl get pod resources-demo -o jsonpath='{.status.qosClass}'; echo
   ```
   Expected: `Burstable` (requests < limits).

3. "The scheduler used requests to place it — see the node's allocation."
   ```bash
   kubectl describe node $(kubectl get pod resources-demo -o jsonpath='{.spec.nodeName}') | grep -A4 'Allocated resources'
   ```
   Expected: the request amounts counted against the node.

4. "Memory over the limit → OOMKilled (conceptual: a Pod requesting more than its
   64Mi limit would be killed). CPU over limit → throttled, not killed."

5. "Clean up."
   ```bash
   kubectl delete -f 00-manifests/resources-demo.yaml
   ```

**✅ Conclusions:**

- requests = reserved for scheduling; 
- limits = hard runtime cap.
- CPU over limit → throttle; 
- memory over limit → OOMKill.
- QoS (Guaranteed/Burstable/BestEffort) sets eviction priority.
