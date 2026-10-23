- You may specify either the "iops" or "iopsPerGb" parameters, not both.
  Specifying both parameters will result in an invalid StorageClass.

| Volume Type                | Min total IOPS | Max total IOPS | Max IOPS per GB |
| -------------------------- | -------------- | -------------- | --------------- |
| io1                        | 100            | 64000          | 50              |
| io2 (blockExpress = false) | 100            | 64000          | 500             |
| io2 (blockExpress = true)  | 100            | 256000         | 500             |
| gp3                        | 3000           | 16000          | 500             |

```
Read more: https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/master/docs/parameters.md

# apply
kubectl apply -f manifest

# Clean
kubectl delete -f manifest
```
