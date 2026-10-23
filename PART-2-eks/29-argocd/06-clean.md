```
# delete argocd app
kubectl delete ns argocd

# delete myapp ns
kubectl delete ns myapp
```

💡 You have to delete `argocd namespace` first to delete `myapp` namespace. Or
k8s will create all resources automatically in `myapp` ns.
