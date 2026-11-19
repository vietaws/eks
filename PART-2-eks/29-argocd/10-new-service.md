Add a new service (`orders`) with one values file and no copied YAML.

Repo stage: tag `v5-new-service` in https://github.com/vietaws/argocd-demo.git

# 1️⃣ Compare the effort

| | Plain manifests | Helm chart |
|---|---|---|
| Files to add | `deployment.yaml` + `service.yaml` (+ ingress, ...) | 1 values file |
| Lines to write | ~30 and growing | ~12 |
| Later template fix | Edit every copy | Edit the chart once |

# 2️⃣ New values file

`envs/dev/orders.yaml`

```yaml
replicas: 1
image:
  repository: nginx
  tag: stable
containerPort: 80
service:
  port: 80
env:
  - name: LOG_LEVEL
    value: debug
```

The chart uses `{{ .Release.Name }}` for names, so this creates `orders` and `orders-service` and does not collide with `myapp`.

# 3️⃣ Test locally, then deploy

```
helm template orders charts/myapp -f envs/dev/orders.yaml

# push the repo
git push origin main --tags

# create the Application
kubectl apply -f helm/application-orders.yaml
```

# 4️⃣ Verify

```
kubectl get deploy,svc -n orders

NAME                     READY   UP-TO-DATE   AVAILABLE
deployment.apps/orders   1/1     1            1
```

Check ArgoCD UI: `http://localhost:8080` - a third app appears.
