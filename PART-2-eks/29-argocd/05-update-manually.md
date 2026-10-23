Update cluster manually from kubectl

# 1️⃣ Check Pod

```
# Pod
kubectl get pod -n myapp

NAME                    READY   STATUS    RESTARTS   AGE
myapp-6645b78bb-4jj98   1/1     Running   0          22m
myapp-6645b78bb-689zm   1/1     Running   0          22m
myapp-6645b78bb-cmx6m   1/1     Running   0          10s

# Deployments
kubectl get deploy -n myapp
NAME    READY   UP-TO-DATE   AVAILABLE   AGE
myapp   3/3     3            3           23m
```

# 2️⃣ Manual update EKS cluster

```
# Edit Deployment
kubectl -n myapp edit deployment myapp

# update replicas from 3 to 4 & SAVE

# Verify Deployment
kubectl -n myapp get deployments

NAME    READY   UP-TO-DATE   AVAILABLE   AGE
myapp   3/3     3            3           25m
```

✅ ArgoCD helps to manage consistency of K8s deployment env
