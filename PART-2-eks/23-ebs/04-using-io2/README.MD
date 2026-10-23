```
# apply
kubectl apply -f manifest

# delete
kubectl delete -f manifest

# change value to decrease => FAILED
kubectl apply -f manifest
kubectl get pv

# change volume size to increase from 4 to 5 => SUCCESS
kubectl apply -f manifest
kubectl get pv

```
