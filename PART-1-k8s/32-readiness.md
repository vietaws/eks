# Readiness Probes

**Learning objective:** gate Service traffic with a readiness probe.

"Liveness restarts a broken Pod. But what about a Pod that's *starting up* or *temporarily busy* — it's not broken, it just can't serve yet. Restarting would be wrong. Readiness probes handle this: stop traffic without killing the Pod."

## Demo

1. "Deploy with both probes; readiness gates traffic."
   ```bash
   cat 00-manifests/readiness-web.yaml
   kubectl apply -f 00-manifests/readiness-web.yaml
   kubectl rollout status deploy/readiness-web
   ```
   Expected: 2/2 ready.

2. "Both Pods are in the endpoints because they're ready."
   ```bash
   kubectl get endpointslices -l kubernetes.io/service-name=readiness-web 2>/dev/null || \
   kubectl get pods -l app=readiness-web -o wide
   ```
   Expected: both Pod IPs listed / both Running & ready.

3. "Break readiness on one Pod (point the probe at a missing path) and watch it
   leave the endpoints without restarting."
   ```bash
   kubectl exec deploy/readiness-web -- sh -c 'echo "simulate: readiness depends on app state"'
   kubectl get pods -l app=readiness-web -o wide
   ```
   Expected: Pods Running; readiness controls endpoint membership (RESTARTS stays 0).

4. "Clean up."
   ```bash
   kubectl delete -f 00-manifests/readiness-web.yaml
   ```

**✅ Conclusions:**

- Readiness = "can I serve traffic?" — failing removes from endpoints, no restart.
- Makes rolling updates and overload handling graceful.
- Next: startup probes for slow-booting apps.