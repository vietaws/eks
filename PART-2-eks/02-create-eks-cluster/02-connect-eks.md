# 🌻 There are 3 ways you can get the kubeconfig.

## Method 0

```bash
### Tab 1

export KUBECONFIG=~/.kube/c1.yaml
aws eks update-kubeconfig --name c1 --alias vietvn

export CLUSTER_NAME="upg-mng"
export KUBECONFIG=~/.kube/${CLUSTER_NAME}.yaml
aws eks update-kubeconfig --name ${CLUSTER_NAME} 

--alias automode

kubectl get nodes

export CLUSTER_NAME=c1

eksctl utils write-kubeconfig --cluster ${CLUSTER_NAME} --kubeconfig ~/.kube/${CLUSTER_NAME}.yaml

eksctl utils write-kubeconfig --cluster c1 --region ap-southeast-1 --set-kubeconfig-context=true
# eksctl has no alias flag, so rename afterwards
  
# rename an existing context
kubectl config rename-context <old-context-name> dev-sg
kubectl config get-contexts          # list the names

kubectl --context dev-sg get nodes
# OR
kubectl config use-context dev-sg
  
### Tab 2
export KUBECONFIG=~/.kube/c2.yaml
aws eks update-kubeconfig --name c2 --region ap-southeast-1
kubectl get nodes
```

## Method 1

Command

```
aws eks update-kubeconfig --alias <alias> --name <clustername> --region <region>
```

Example

```
aws eks update-kubeconfig --alias vietvn --name vietvn
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
