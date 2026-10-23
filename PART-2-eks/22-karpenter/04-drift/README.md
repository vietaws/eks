# Benefits

- Triggered by changing on NodePools, Ec2NodeClass. eg: Instance type, node...

- Upgrade data plane. AWS release new AMIs, Karpenter will check on System
  Parameter Store and change worker node AMI.

- Enabled in `karpenter-global-setting` configmap. Enabled by default after
  `v0.32.x`

- In this demo, we will use instance type `m` in the first configure. And, we
  change to `c` instance type. You will see karpenter update the data plane.

# Create nodepool & nodeclass

```
# Command
kubectl edit nodepools default
// Change type: [m, r, c] to [m]
// Output: nodepool.karpenter.sh/default edited

# Get nodepool
kubectl get nodepools

# describe
kubectl describe nodepools default
```

# Scale Up deployment

```
# Deploy App
kubectl apply -f manifests/app.yaml

kubectl scale deployment inflate --replicas 2
kubectl logs -f -n kube-system -l app.kubernetes.io/name=karpenter -c controller

```

# Change instance type

```
# Command
kubectl edit nodepools default
// Change type: [m] to [c]
// Output: nodepool.karpenter.sh/default edited

# Get nodepool
kubectl get nodepools

# describe
kubectl describe nodepools default

```

# Clean Up

```
# Delete deployment
kubectl delete deployment inflate

```
