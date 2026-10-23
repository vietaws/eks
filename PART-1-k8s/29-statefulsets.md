# StatefulSets

**Learning objective:** run a stateful app with stable identity and per-Pod storage.

"Deployments treat Pods as interchangeable cattle. But databases need stable names and their own disks — `web-0` must always be `web-0` with its own data. That's a StatefulSet."

## Demo

1. "Apply the headless Service + StatefulSet (2 replicas)."
   ```bash
   cat 00-manifests/web-sts.yaml
   kubectl apply -f 00-manifests/web-sts.yaml
   kubectl rollout status statefulset/web --timeout=120s
   ```
   Expected: Pods come up in order.

2. "Stable ordinal names — not random hashes."
   ```bash
   kubectl get pods -l app=web-sts
   ```
   Expected: exactly `web-0` and `web-1`.

3. "Each Pod got its OWN PVC from the template."
   ```bash
   kubectl get pvc
   ```
   Expected: `www-web-0` and `www-web-1`, both Bound.

4. "Write unique data into web-0's volume; it stays tied to web-0."
   ```bash
   kubectl exec web-0 -- sh -c 'echo "I am web-0" > /usr/share/nginx/html/id.txt'
   kubectl delete pod web-0            # StatefulSet recreates web-0
   kubectl wait --for=condition=Ready pod/web-0 --timeout=90s
   kubectl exec web-0 -- cat /usr/share/nginx/html/id.txt
   ```
   Expected: `I am web-0` — same name, same volume, after recreation.

5. "Clean up (note: deleting a StatefulSet leaves its PVCs by design)."
   ```bash
   kubectl delete -f 00-manifests/web-sts.yaml
   kubectl delete pvc www-web-0 www-web-1
   ```