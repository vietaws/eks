Deploy dev and prod from one chart with one values file per environment.

Repo stage: tag `v4-helm-envs` in https://github.com/vietaws/argocd-demo.git

# 1️⃣ What changed in the manifest repo

```
argocd-demo/
├── charts/myapp/          # one chart
└── envs/
    ├── dev/values.yaml    # replicas: 1, LOG_LEVEL=debug, ALB vietvn-argocd-dev-alb
    └── prod/values.yaml   # replicas: 3, LOG_LEVEL=info, ALB vietvn-argocd-prod-alb
```

`app/` and `app-prod/` stay in the repo as the plain-manifest baseline, but nothing syncs them after this step.

⚠️ Do not apply `../application.yaml` and `helm/application-dev.yaml` at the same time. Both use the Application name `vietaws-argo-application`, so the last one applied wins.

# 2️⃣ Update the Applications

The new files use the same Application names, so `kubectl apply` updates the existing apps in place.

```
# in the argocd-demo repo
git push origin main --tags

# in this folder
# once per cluster: the IngressClass the chart's Ingress uses (needs the AWS Load Balancer Controller)
kubectl apply -f argocd-demo/alb/ingress-class.yaml

kubectl apply -f helm/application-dev.yaml
kubectl apply -f helm/application-prod.yaml
```

Key part of the Application:

```yaml
source:
  path: charts/myapp
  helm:
    releaseName: myapp                 # keeps names myapp / myapp-service
    valueFiles:
      - ../../envs/dev/values.yaml     # relative to the chart path
```

💡 Without `releaseName`, Argo CD uses the Application name as the release name and the resources would be renamed.

# 3️⃣ Verify

```
kubectl get deploy -n myapp
kubectl get deploy -n myapp-prod
kubectl -n myapp get deploy myapp -o jsonpath='{.spec.template.spec.containers[0].env}'
kubectl get ingress -n myapp
kubectl get ingress -n myapp-prod
```

✅ Dev has 1 replica and prod has 3, with no downtime during the switch because names and selectors did not change.

✅ Each environment has its own ALB. The ADDRESS column fills in after 2-3 minutes, and the ALBs `vietvn-argocd-dev-alb` and `vietvn-argocd-prod-alb` appear in the EC2 console (Load Balancers).

⚠ If an Ingress has no ADDRESS, run `kubectl describe ingress -n myapp` and check the `aws-load-balancer-controller` logs in `kube-system`.

# 4️⃣ Where do the values live?

| Component | Holds the values? |
|---|---|
| Git repo (`envs/*/values.yaml`) | ✅ Source of truth |
| Argo CD | Only the file paths in the Application |
| Helm | Nothing, it only merges chart defaults and your files |
| Kubernetes | Only the rendered manifests |

```
helm list -A
# empty: Argo CD uses `helm template` and does not create Helm releases
```

# 5️⃣ Try it

1. Change `replicas` in `envs/prod/values.yaml`, then push. Only prod changes.
2. Add a label to `charts/myapp/templates/deployment.yaml`, then push. Dev and prod both change. This is the edit that took two folders in the plain version.

⚠️ Do not put secrets in values files. The rendered manifests contain them in plain text. Use External Secrets Operator or SOPS.
