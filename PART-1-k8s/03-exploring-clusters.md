# Exploring K8s Cluster

```bash
# Cluster health & nodes
kubectl cluster-info
kubectl get nodes

# Control-plane components run as Pods here
kubectl get pods -n kube-system

# The four daily-driver verbs
kubectl get pods -A
kubectl describe node vietvn-k8s-control-plane | head -n 25
# kubectl logs <pod> -n <ns>
# kubectl exec -it <pod> -- sh

# Namespaces
kubectl get namespaces

# Discoverability habits
kubectl explain pod.spec.containers | head -n 20
kubectl run demo --image=nginx --dry-run=client -o yaml | head -n 15
```

Expected: healthy cluster info, kube-system system Pods, 4 built-in namespaces.