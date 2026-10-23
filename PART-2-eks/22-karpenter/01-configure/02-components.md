# NodePool

- Define list of Amazon EC2 will be provisioned

- Attributes: Instance type, family, size, cpu limit, AZ

- Support multiple NodePool

# NodeClass

- Enabled configuration for AWS related such as: subnet, ami, security group of
  node

- One `NodeClass` can be referred by many `NodePool`

```
# NodePool 1
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: np1
spec:
  template:
    spec:
      nodeClassRef:
        apiVersion: karpenter.k8s.aws/v1beta1
        kind: EC2NodeClass
        name: team-a

# NodePool 2
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: np2
spec:
  template:
    spec:
      nodeClassRef:
        apiVersion: karpenter.k8s.aws/v1beta1
        kind: EC2NodeClass
        name: team-a

#NodeClass
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: team-a
spec
```
