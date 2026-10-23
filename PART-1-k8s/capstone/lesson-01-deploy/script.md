# Capstone Part 1 — Deploy the Multi-Tier App

**Learning objective:** deploy a three-tier app and verify every tier end to end.

"This is the payoff. Every concept from the course — Deployments, Services, ConfigMaps, Secrets, a StatefulSet with persistent storage, and an Ingress — assembled into one real application, installed with a single Helm command."

## Concept
Reference the architecture diagram in `capstone/README.md`. Three tiers:

- **web** (nginx Deployment) — the frontend, behind a Service.
- **api** (http-echo Deployment) — reads config from a ConfigMap and a password from a Secret.
- **redis** (StatefulSet) — the datastore, with its own PVC and a password from the same Secret; fronted by a headless Service.

An Ingress routes `/` to web and `/api` to api. It's all one Helm chart.

## Demo
1. "Lint the chart, create a namespace, install."
   ```bash
   helm lint capstone/guestbook
   kubectl create namespace course-capstone
   helm install gb ./capstone/guestbook -n course-capstone
   ```
   Expected: `STATUS: deployed`.

2. "Watch all three tiers come up."
   ```bash
   kubectl -n course-capstone rollout status deploy/gb-web
   kubectl -n course-capstone rollout status deploy/gb-api
   kubectl -n course-capstone rollout status statefulset/gb-redis
   ```
   Expected: web 2/2, api 2/2, redis 1/1.

3. "See everything the chart created."
   ```bash
   kubectl -n course-capstone get deploy,sts,svc,ingress,cm,secret,pvc
   ```
   Expected: 2 Deployments, 1 StatefulSet, 3 Services, 1 Ingress, ConfigMap,
   Secret, and a bound PVC `data-gb-redis-0`.

4. "Prove the datastore persists and uses the Secret's password."
   ```bash
   kubectl -n course-capstone exec gb-redis-0 -- redis-cli -a s3cr3t-redis set greeting "hi"
   kubectl -n course-capstone exec gb-redis-0 -- redis-cli -a s3cr3t-redis get greeting
   ```
   Expected: `hi` (auth succeeded; data stored on the PVC).

5. "Route external traffic through the Ingress."
   ```bash
   HOST=ingress-nginx-controller.ingress-nginx.svc.cluster.local
   kubectl -n course-capstone run c --image=curlimages/curl:8.11.1 --restart=Never -i --rm -- curl -s http://$HOST/ | grep -o '<title>.*</title>'
   kubectl -n course-capstone run c --image=curlimages/curl:8.11.1 --restart=Never -i --rm -- curl -s http://$HOST/api
   ```
   Expected: nginx welcome for `/`; the API message for `/api`.

## Recap
- One Helm install → a full multi-tier app: web + api + redis.
- ConfigMap/Secret feed config; the StatefulSet persists data; Ingress routes.
- Next: treat it as a product — upgrade and roll back with Helm.
