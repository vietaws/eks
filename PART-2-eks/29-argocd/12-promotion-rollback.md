Day-2 workflow: promote a version, see drift healed, and roll back, all through Git.

Prerequisite: the ApplicationSet from `11-applicationset.md`.

# 1️⃣ Dev auto-syncs, prod needs a manual sync

In `helm/appset.yaml`, change the prod element:

```yaml
- name: vietaws-argo-application-prod
  ...
  autoSync: false      # was true
```

```
kubectl apply -f helm/appset.yaml
```

The generated prod Application no longer has `syncPolicy.automated`. Dev and orders are unchanged.

# 2️⃣ Promote: dev first, then prod

1. In the manifest repo, change `image.tag` in `envs/dev/values.yaml` to a tag that exists in your registry (for example `v2`), commit, and push.
2. Dev syncs by itself (within the 3-minute poll). Check it:
   ```
   kubectl get deploy myapp -n myapp -o jsonpath='{.spec.template.spec.containers[0].image}'
   ```
3. When dev looks good, make the same change in `envs/prod/values.yaml` through a pull request.
4. Prod shows **OutOfSync** and nothing changes yet:
   ```
   kubectl get application vietaws-argo-application-prod -n argocd
   ```
5. Sync prod from the UI (**SYNC**) or with:
   ```
   argocd app sync vietaws-argo-application-prod
   ```

💡 Promotion is a reviewed Git change plus a deliberate sync. No script touches the cluster directly.

# 3️⃣ Drift is corrected on dev

```
kubectl scale deploy myapp -n myapp --replicas=5
kubectl get deploy myapp -n myapp -w
```

`selfHeal` sets it back to the value in `envs/dev/values.yaml`. On prod (auto-sync off), the same change shows as **OutOfSync** and waits for a sync.

# 4️⃣ Roll back with Git

```
git revert <commit-that-changed-prod-tag>
git push origin main
argocd app sync vietaws-argo-application-prod
```

The previous image tag is rendered and applied again. The Git history is the audit log.

# 5️⃣ Why not `helm rollback`?

Argo CD renders the chart with `helm template` and applies the result itself, so no Helm release exists in the cluster.

```
helm list -A
helm rollback myapp 1 -n myapp
# Error: release: not found
```

Rolling back means changing Git, which also keeps Git and the cluster consistent. A `helm rollback` would only create drift.
