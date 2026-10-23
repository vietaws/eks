# Liveness Probes

**Learning objective:** use a liveness probe to auto-restart an unhealthy container.

"A process can be 'running' but wedged — deadlocked, out of connections, stuck.
Kubernetes can't know unless you tell it how to check. That's a liveness probe: fail it, and the container gets restarted automatically."

## Demo

1. "This container is healthy for 20s, then deletes its health file."
   ```bash
   cat 00-manifests/liveness-demo.yaml
   kubectl apply -f 00-manifests/liveness-demo.yaml
   kubectl wait --for=condition=Ready pod/liveness-demo --timeout=30s
   ```
   Expected: Pod Running, restartCount 0.

2. "After the file is gone, the probe fails and the kubelet kills it — watch the events."
   ```bash
   sleep 25
   kubectl describe pod liveness-demo | grep -A6 Events: | tail -4
   ```
   Expected: `Liveness probe failed` and `Container app failed liveness probe, will be restarted`.

3. "Give it a bit — the restart count climbs (restart registers ~50–60s in)."
   ```bash
   sleep 35
   kubectl get pod liveness-demo        # RESTARTS >= 1
   ```
   Expected: `RESTARTS` is 1 or more.

4. "Clean up."
   ```bash
   kubectl delete -f 00-manifests/liveness-demo.yaml
   ```

**✅ Conclusions:**

- Liveness probe failing → kubelet restarts the container.
- Types: exec / httpGet / tcpSocket; tune with delay/period/threshold.
- Next: readiness — controlling *traffic*, not restarts.