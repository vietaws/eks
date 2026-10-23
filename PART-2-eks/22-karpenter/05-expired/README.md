# Benefits

- Expire nodes after certain amount of time

- Force AMI refresh

- Recycle node for security concerns

- Using `tain` to prevent pods `karpenter.sh/disruption:NoSchedule`

- Time configure Options:
  - 720h (720 hours)
  - 14d (14 days)

# Create nodepool & nodeclass

```
# Example 1
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
    #instance type...
  disruption:
    consolidationPolicy: WhenUnderutilized # WhenEmpty
    expireAfter: 720h # 30 * 24h = 720h

# Example 2
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
    #instance type...
  disruption:
    consolidationPolicy: WhenUnderutilized # WhenEmpty
    expireAfter: Never

# Example 3
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
    #instance type...
  disruption:
    consolidationPolicy: WhenUnderutilized # WhenEmpty
    expireAfter: 360h
    consolidateAfter: 30s
```
