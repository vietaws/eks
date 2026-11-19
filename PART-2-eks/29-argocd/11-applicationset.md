Generate the Applications from one list instead of one YAML file per app.

Repo stage: the manifest repo is unchanged. The new file is `helm/appset.yaml` in this folder.

The ApplicationSet controller is included in the standard Argo CD install from `02-install.md`.

# 1️⃣ The ApplicationSet

`helm/appset.yaml` has a list generator with one element per Application:

```yaml
generators:
  - list:
      elements:
        - name: vietaws-argo-application
          release: myapp
          namespace: myapp
          valuesFile: envs/dev/values.yaml
          autoSync: true
        - name: vietaws-argo-application-prod
          ...
        - name: orders-dev
          ...
```

The template turns each element into an Application using `charts/myapp`:

```yaml
helm:
  releaseName: '{{.release}}'
  valueFiles:
    - '../../{{.valuesFile}}'
```

`preserveResourcesOnDeletion: true` keeps the workloads running if the ApplicationSet or an element is removed.

# 2️⃣ Replace the hand-written Applications

⚠️ The new ApplicationSet generates Applications with the same names. Delete the old ones first, so there is no conflict.

```
# Confirm there is no cascading finalizer. The output must be empty.
kubectl get applications -n argocd -o jsonpath='{.items[*].metadata.finalizers}'

# Delete only the Application objects. Without the finalizer the workloads keep running.
kubectl delete application vietaws-argo-application vietaws-argo-application-prod orders-dev -n argocd

# Create the ApplicationSet. It recreates the Applications and they adopt the running resources.
kubectl apply -f helm/appset.yaml
```

If the finalizer output is not empty, do not delete. Add `--cascade=orphan` or remove the finalizer first, or the Deployments will be deleted too.

# 3️⃣ Verify

```
kubectl get applicationset -n argocd
kubectl get applications -n argocd

NAME                            SYNC STATUS   HEALTH STATUS
orders-dev                      Synced        Healthy
vietaws-argo-application        Synced        Healthy
vietaws-argo-application-prod   Synced        Healthy

kubectl get pods -A | grep -E "myapp|orders"
```

✅ The Pods keep their original age, so nothing was restarted.

# 4️⃣ Try it

Add a new element to `helm/appset.yaml` (for example `orders-prod` with `envs/prod/orders.yaml`), then apply the file. A new Application and namespace appear with no new Application YAML.

💡 Plain Applications are fine for 1 to 3 apps. An ApplicationSet pays off when the list grows, or when you use generators (Git directories, clusters) so that adding a folder or a cluster creates the apps for you.
