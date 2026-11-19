```
# delete argocd app
kubectl delete ns argocd

# delete app namespaces
kubectl delete ns myapp myapp-prod orders
```

💡 You have to delete `argocd namespace` first to delete `myapp` namespace. Or k8s will create all resources automatically in `myapp` ns.

💡 The ApplicationSet uses `preserveResourcesOnDeletion: true`, so deleting it (or the `argocd` namespace) leaves the workloads running. That is why the app namespaces are deleted explicitly.
