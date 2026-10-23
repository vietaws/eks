# Deployments

**Learning objective:** create a Deployment and see how it owns a ReplicaSet which owns Pods.

## Create Deployment

0. "Imperative first — one command creates the whole thing."
   ```bash
   kubectl create deployment web --image=nginx:1.26-alpine --replicas=3
   kubectl get deploy,rs,pods -l app=web
   ```
   Expected: Deployment + ReplicaSet + 3 Pods appear immediately. Great for experiments. Now let's do it the committable way.

   ```bash
   kubectl delete deployment web     # clear the imperative one first
   ```

1. "Apply a Deployment for 3 nginx Pods — the manifest we keep in git."
   ```bash
   kubectl apply -f 00-manifests/web-deploy.yaml
   kubectl rollout status deploy/web
   ```
   Expected: `deployment "web" successfully rolled out`.

2. "See all three tiers at once."
   ```bash
   kubectl get deploy,rs,pods -l app=web
   ```
   Expected: 1 Deployment, 1 ReplicaSet, 3 Pods.

3. "The Deployment created that ReplicaSet — confirm ownership."
   ```bash
   kubectl get rs -l app=web -o jsonpath='{.items[0].metadata.ownerReferences[0].kind}'; echo
   ```
   Expected: `Deployment`.

4. "Delete the whole ReplicaSet — the Deployment just makes a new one."
   ```bash
   kubectl delete rs -l app=web
   sleep 3
   kubectl get rs -l app=web
   ```
   Expected: a fresh ReplicaSet appears; Pods return.

**Conclusions:**

- Deployment → ReplicaSet → Pods.
- You manage the Deployment; it manages the rest.

## Scaling

"Traffic spike? You need more Pods, now. Scaling in Kubernetes is changing one number. Let's go from 3 to 5 to 1 and watch it happen."

**Learning objective:** scale a Deployment up and down, imperatively and declaratively.


1. "Current state: 3 Pods."
   ```bash
   kubectl get deploy web
   ```
   Expected: `READY 3/3`.

2. "Scale up imperatively."
   ```bash
   kubectl scale deploy/web --replicas=5
   kubectl get pods -l app=web -w
   ```
   Expected: two new Pods appear; 5/5. (Ctrl-C to stop.)

3. "Scale down."
   ```bash
   kubectl scale deploy/web --replicas=1
   kubectl get pods -l app=web
   ```
   Expected: 4 Pods terminating; settles at 1.

4. "Careful — the YAML still says 3. Re-applying it wins."
   ```bash
   kubectl apply -f labs/web-deploy.yaml
   kubectl get deploy web
   ```
   Expected: back to `3/3` — the manifest is the source of truth.

**Conclusions:**

- Scaling = change `replicas`; the controller reconciles.
- Imperative is quick but drifts from your YAML.

## Rollout - Upgrading App Without Downtime

**Learning objective:** perform a zero-downtime update and roll back a bad release.

1. "We're on nginx 1.26. Roll forward to 1.27 and watch the roll."
   ```bash
   kubectl get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
   kubectl set image deploy/web web=nginx:1.27-alpine
   kubectl rollout status deploy/web
   ```
   Expected: status prints Pods updating a few at a time, then "successfully rolled out".

2. "Two revisions now exist."
   ```bash
   kubectl rollout history deploy/web
   kubectl get rs -l app=web
   ```
   Expected: revisions 1 and 2; an old RS at 0 replicas, new RS at 3.

3. "Pretend 1.27 is broken. Roll back — instantly."
   ```bash
   kubectl rollout undo deploy/web
   kubectl rollout status deploy/web
   kubectl get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
   ```
   Expected: image back to `nginx:1.26-alpine`.

4. "You can also roll back to a specific revision."
   ```bash
   kubectl rollout undo deploy/web --to-revision=2
   kubectl rollout status deploy/web
   ```
   Expected: forward to 1.27 again.

5. "Clean up."
   ```bash
   kubectl delete -f 00-manifests/web-deploy.yaml
   ```

**✅ Conclusions:**

- New image = new ReplicaSet; Pods shift gradually = zero downtime.
- Old ReplicaSets are kept at 0 for instant rollback.
- `rollout status / history / undo` are your release toolkit.

## Strategies - Tune the RollingUpdate

**Learning objective:** tune a RollingUpdate with maxSurge/maxUnavailable and contrast with Recreate.

1. "This Deployment sets maxSurge=1, maxUnavailable=1, and a readiness probe."
   ```bash
   cat 00-manifests/web-strategy.yaml
   kubectl apply -f 00-manifests/web-strategy.yaml
   kubectl rollout status deploy/web
   ```
   Expected: 4 Pods become ready.

2. "Roll to a new image and watch the counts stay within the knobs."
   ```bash
   kubectl set image deploy/web web=nginx:1.27-alpine
   kubectl get pods -l app=web -w
   ```
   Expected: total Pods never exceed 5 (4+surge), ready never below 3. Ctrl-C to stop.

3. "Confirm the roll finished."
   ```bash
   kubectl rollout status deploy/web
   ```
   Expected: successfully rolled out.

4. "Clean up."
   ```bash
   kubectl delete -f 00-manifests/web-strategy.yaml
   ```