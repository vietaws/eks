# 🌻 There are 2 ways you can get the kubeconfig.

## Method 1

Command

```
aws eks update-kubeconfig --alias <alias> --name <clustername> --region <region>
```

Example

```
aws eks update-kubeconfig --alias vietvn --name vietvn --profile eks
```

Output

```
Added new context arn:aws:eks:ap-southeast-1:ACCOUNTID:cluster/cdk to /Users/vietvn/.kube/config
```

✅ Verify

```
kubectl config get-contexts
```

## Method 2

```

eksctl utils write-kubeconfig --cluster=<clustername>

```
