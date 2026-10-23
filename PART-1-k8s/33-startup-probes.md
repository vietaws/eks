# Startup Probes

**Learning objective:** protect a slow-starting container with a startup probe.

"Your app takes 40 seconds to boot — a JVM warming up, a big migration. A liveness probe would kill it mid-boot, forever. Startup probes solve this: 'don't even start liveness checks until I've finished booting.'"

## Demo

1. "This app is 'starting' for ~10s; the startup probe waits for it."
   ```bash
   cat 00-manifests/startup-demo.yaml
   kubectl apply -f 00-manifests/startup-demo.yaml
   ```
   Expected: Pod created; not Ready yet.

2. "During startup it's not ready; liveness is paused (no premature kill)."
   ```bash
   sleep 5
   kubectl get pod startup-demo -o jsonpath='{.status.containerStatuses[0].ready}'; echo   # false
   ```
   Expected: `false` while still starting.

3. "After startup completes, it becomes ready and liveness takes over."
   ```bash
   sleep 10
   kubectl get pod startup-demo -o jsonpath='{.status.containerStatuses[0].ready}'; echo   # true
   ```
   Expected: `true`.

4. "Clean up."
   ```bash
   kubectl delete -f 00-manifests/startup-demo.yaml
   ```

**✅ Conclusions:**

- Startup probe gates liveness/readiness during boot.
- Budget = failureThreshold × periodSeconds — size it for your slowest start.
- Next: resource requests and limits.