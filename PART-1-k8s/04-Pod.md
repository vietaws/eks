# Your First Pod (Imperative)

**Learning objective:** create, inspect, reach, and delete a Pod using imperative commands.

`kubectl run` creates a single Pod directly — no **Deployment**, no YAML. In **Production** you'll use
Deployments, but understanding the raw Pod first makes everything else click.

Pod manifest: https://kubernetes.io/docs/concepts/workloads/pods/

## 1 - Web Pod - Imperative
1. "Run nginx as a Pod."
   ```bash
   kubectl run web --image=nginx:1.27-alpine
   kubectl get pods -o wide
   ```
   Expected: Pod `web` goes Pending → ContainerCreating → Running, with a node + IP.

2. "Inspect it — this is your most-used command."
   ```bash
   kubectl describe pod web | head -n 30
   ```
   Expected: events showing Scheduled → Pulling → Created → Started.

3. "Reach it from your laptop with port-forward."
   ```bash
   kubectl port-forward pod/web 8080:80
   # in another terminal:
   curl -s localhost:8080 | head -n 5
   ```
   Expected: the nginx welcome HTML. Ctrl-C to stop the forward.

4. "Clean up."
   ```bash
   kubectl delete pod web
   ```
   Expected: `pod "web" deleted`. Nothing recreates it — it was a bare Pod.

**Conclusion**:

- `kubectl run` = one Pod, fast.
- describe shows the event timeline; port-forward reaches it locally.
- A bare Pod has no self-healing — delete it and it's gone. Next: declarative YAML.

## 2 - Web Pod - Manifest (Declarative)

0. "Don't hand-write YAML from scratch — let the CLI scaffold it. Imperative first:"
   ```bash
   kubectl run web --image=nginx:1.27-alpine --port=80 \
     --dry-run=client -o yaml > web-pod.yaml
   cat web-pod.yaml
   ```
   Expected: a valid starting Pod manifest, nothing created yet. This is the bridge from imperative to declarative — generate, then refine and commit.

1. "Here's the refined manifest — note the four keys and the resource requests/limits."
   ```bash
   cat 00-manifests/web-pod.yaml
   ```
   Expected: `apiVersion: v1`, `kind: Pod`, metadata labels, container spec.

2. "Validate before applying — server-side dry run catches errors."
   ```bash
   kubectl apply -f 00-manifests/web-pod.yaml --dry-run=server
   ```
   Expected: `pod/web created (server dry run)` — nothing actually created.

3. "Apply for real and watch it come up."
   ```bash
   kubectl apply -f 00-manifests/web-pod.yaml
   kubectl get pod web -o wide
   ```
   Expected: Pod `web` Running with an IP and a node.

4. "See the status the system filled in."
   ```bash
   kubectl get pod web -o jsonpath='{.status.phase}{"\n"}'
   kubectl get pod web -o yaml | grep -A6 '^status:'
   ```
   Expected: `Running`; status block with conditions and podIP.

5. "Apply again — idempotent, no error."
   ```bash
   kubectl apply -f 00-manifests/web-pod.yaml
   ```
   Expected: `pod/web unchanged`.

6. "Clean up."
   ```bash
   kubectl delete -f labs/web-pod.yaml
   ```

**Conclusions**:

- Four keys: apiVersion, kind, metadata, spec.
- You write spec; Kubernetes writes status.
- apply is declarative and idempotent. Next: more than one container in a Pod.

## 3 - Pod - Multi Containers

**Learning objective:** build a two-container Pod where a sidecar reads what the app writes.

1. "Look at the manifest — one volume, two containers mounting it."
   ```bash
   cat 00-manifests/web-with-sidecar.yaml
   ```
   Expected: `volumes: shared-logs (emptyDir)` mounted in both containers.

2. "Apply it."
   ```bash
   kubectl apply -f 00-manifests/web-with-sidecar.yaml
   kubectl get pod web-with-sidecar -o wide
   ```
   Expected: Pod `READY 2/2` — two containers running.

3. "Read the APP container's own output."
   ```bash
   kubectl logs web-with-sidecar -c app | tail -3
   ```
   Expected: `app heartbeat #N` lines.

4. "Now read the SIDECAR — it's tailing the same file the app wrote."
   ```bash
   kubectl logs web-with-sidecar -c log-sidecar | tail -3
   ```
   Expected: the same heartbeat lines — proof they share the volume.

5. "Prove the shared network too — exec into the sidecar and hit localhost."
   ```bash
   kubectl exec web-with-sidecar -c log-sidecar -- wget -qO- 127.0.0.1 || echo "(no server on :80 in this demo)"
   ```
   Expected: either content or the fallback — the point is `localhost` is shared.

6. "Clean up."
   ```bash
   kubectl delete -f 00-manifests/web-with-sidecar.yaml
   ```

**Conclusions**:

- Containers in a Pod share volumes and localhost.
- Sidecar = helper container on the app's lifecycle.
- `kubectl logs -c <container>` targets a specific container. Next: the lifecycle.

## 4 - Pod LifeCycle

**Learning objective:** describe Pod phases, init containers, and restartPolicy behavior.

1. "This Pod has an init container that sleeps, then a main that exits after 10s
   with restartPolicy Always."
   ```bash
   cat 00-manifests/lifecycle-demo.yaml
   ```
   Expected: `initContainers` + `restartPolicy: Always`.

2. "Apply and watch it pass through Init."
   ```bash
   kubectl apply -f 00-manifests/lifecycle-demo.yaml
   kubectl get pod lifecycle-demo -w
   ```
   Expected: `Init:0/1` → `PodInitializing` → `Running`. Ctrl-C to stop watching.

3. "See the init container's output."
   ```bash
   kubectl logs lifecycle-demo -c init-wait
   ```
   Expected: `init: preparing...` then `init: done`.

4. "The main container exits every 10s; with Always it restarts. Watch the count."
   ```bash
   sleep 14
   kubectl get pod lifecycle-demo
   ```
   Expected: `RESTARTS` is 1 or more.

5. "Clean up."
   ```bash
   kubectl delete -f 00-manifests/lifecycle-demo.yaml
   ```

**Conclusions:**

- Phases: Pending → Running → Succeeded/Failed.
- Init containers gate the app containers; they run once, in order.
- restartPolicy explains climbing RESTARTS. Next: debugging when things go wrong.

## 5 - Debugging Broken Pod

**Learning objective:** diagnose common Pod failures with describe, logs, exec, and events.

1. "Deploy a deliberately broken Pod — a bad image tag."
   ```bash
   kubectl apply -f 00-manifests/broken-pod.yaml
   kubectl get pod broken
   ```
   Expected: `ErrImagePull` then `ImagePullBackOff`.

2. "describe tells us exactly why — read the Events."
   ```bash
   kubectl describe pod broken | tail -n 15
   ```
   Expected: an event like `Failed to pull image ... not found`.

3. "Fix it by patching to a real tag, then confirm."
   ```bash
   kubectl set image pod/broken app=nginx:1.27-alpine
   kubectl get pod broken -w
   ```
   Expected: moves to Running. (Ctrl-C to stop.) 
   Note: editing a Pod's image in place works for this demo; normally you'd fix the manifest and re-apply.

4. "logs for a running/crashed container."
   ```bash
   kubectl logs broken --tail=5
   ```
   Expected: nginx startup logs.

5. "exec in to inspect from the inside."
   ```bash
   kubectl exec -it broken -- sh -c 'nginx -v; ls /etc/nginx'
   ```
   Expected: nginx version + config listing.

6. "Cluster-wide events, newest last."
   ```bash
   kubectl get events --sort-by=.lastTimestamp | tail -n 10
   ```
   Expected: the pull failure and subsequent recovery.

7. "Clean up."
   ```bash
   kubectl delete -f 00-manifests/broken-pod.yaml
   ```

**Conclusions:**

- describe = scheduling/image issues
- logs = in-container crashes.
- exec to inspect live; get events for the big picture.
- Next section: stop babysitting Pods — Deployments manage them for you.