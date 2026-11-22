# NodePool

- Define list of Amazon EC2 will be provisioned

- Attributes: Instance type, family, size, cpu limit, AZ

- Support multiple NodePool

# NodeClass

- Enabled configuration for AWS related such as: subnet, ami, security group of
  node

- One `NodeClass` can be referred by many `NodePool`

# How they connect (API `karpenter.sh/v1`, stable since Karpenter 1.0)

`nodeClassRef` uses `group` + `kind` + `name` (the v1beta1 `apiVersion` field is gone). Full files
are in [`examples/`](examples/). They use `${CLUSTER_NAME}` and `${AWS_REGION}`, so render them with `envsubst < file.yaml | kubectl apply -f -`.

```yaml
# NodePool 1
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: np1
spec:
  template:
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: team-a

---
# NodePool 2 (shares the same NodeClass)
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: np2
spec:
  template:
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: team-a

---
# NodeClass
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: team-a
spec:
  role: KarpenterNodeRole-<cluster>
  amiSelectorTerms:                 # required in v1
    - alias: al2023@latest
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: <cluster>
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: <cluster>
```

> ℹ️ Every selector term needs a filter. Since Karpenter 1.15.3 a term with an empty `tags` map, `name`
> or `ssmParameter` is ignored, and an EC2NodeClass whose terms are all empty becomes `NotReady`.
