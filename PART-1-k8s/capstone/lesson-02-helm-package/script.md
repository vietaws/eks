# Capstone Part 2 — Package & Operate with Helm

**Learning objective:** customize, upgrade, roll back, and package the capstone chart.

"A running app is step one. Operating it — shipping changes safely and rolling back bad ones — is the job. Our whole app is a Helm chart, so that's a few commands."

## Concept

Because the app is a chart, every tier is parameterized in `values.yaml` (images, replica counts, the API message, Redis storage, the Ingress toggle).

You override per environment, upgrade to create a new revision, and roll back instantly if needed — exactly the Helm workflow, now on a real multi-tier app.

## Demo
1. "Review the tunable values."
   ```bash
   helm show values ./capstone/guestbook
   ```
   Expected: web/api/redis/config/secret/ingress knobs.

2. "Upgrade: scale the API to 3 and change its message — revision 2."
   ```bash
   helm upgrade gb ./capstone/guestbook -n course-capstone \
     --set api.replicas=3 --set api.message="guestbook v2"
   kubectl -n course-capstone rollout status deploy/gb-api
   helm history gb -n course-capstone
   ```
   Expected: api at 3 replicas; history shows revision 2.

3. "Roll back to revision 1 instantly."
   ```bash
   helm rollback gb 1 -n course-capstone
   kubectl -n course-capstone get deploy gb-api -o jsonpath='{.spec.replicas}'; echo
   ```
   Expected: back to 2 replicas.

4. "Package the chart as a shareable artifact."
   ```bash
   helm package ./capstone/guestbook -d /tmp
   ls /tmp/guestbook-0.1.0.tgz
   ```
   Expected: a `guestbook-0.1.0.tgz` you could push to a repo.

5. "Tear down the whole app."
   ```bash
   helm uninstall gb -n course-capstone
   kubectl delete namespace course-capstone
   ```

## Recap
- The app is one chart: parameterized, upgradable, rollback-able, packageable.
- You've now built, deployed, operated, and torn down a realistic Kubernetes app.
- Where next: CKAD/CKA certifications, GitOps (Argo CD/Flux), observability (Prometheus/Grafana), and a real cloud cluster (EKS/GKE/AKS). Congratulations! 🥳
