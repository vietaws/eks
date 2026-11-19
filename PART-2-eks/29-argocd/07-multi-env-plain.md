Add a second environment (`prod`) with plain manifests. This shows the cost of duplication before we introduce Helm.

Repo stage: tag `v2-multi-env-plain` in https://github.com/vietaws/argocd-demo.git

# 1️⃣ What changed in the manifest repo

```
argocd-demo/
├── app/           # dev  - 2 replicas  -> namespace myapp
└── app-prod/      # prod - 3 replicas  -> namespace myapp-prod  (copy of app/)
    ├── deployment.yaml
    └── service.yaml
```

The two folders are identical except `replicas: 3`.

# 2️⃣ Push and create the prod Application

```
# in the argocd-demo repo
git push origin main --tags

# in this folder
kubectl apply -f application-prod.yaml
# Output: application.argoproj.io/vietaws-argo-application-prod created
```

# 3️⃣ Verify

```
kubectl get deploy -n myapp
kubectl get deploy -n myapp-prod

NAME    READY   UP-TO-DATE   AVAILABLE   AGE
myapp   3/3     3            3           1m
```

Check ArgoCD UI: `http://localhost:8080` - two apps are listed.

# 4️⃣ Feel the duplication

Try to add a label `team: payments` to every Pod:

- Edit `app/deployment.yaml`
- Edit `app-prod/deployment.yaml`
- Do it again for every new environment and every new service

💡 10 services x 3 environments = 30 near-identical folders.
