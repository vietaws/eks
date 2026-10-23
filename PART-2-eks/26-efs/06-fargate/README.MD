# Create fargate profile

- Fargate profile name: `fg-efs`

- Namespace: `demo`

```
# Command
eksctl create fargateprofile --cluster vietaws5 \
                             --name fg-efs \
                             --namespace demo \
                             --profile eks

eksctl get fargateprofile --cluster vietaws5 --profile eks
// Output

NAME	SELECTOR_NAMESPACE	SELECTOR_LABELS	POD_EXECUTION_ROLE_ARN			SUBNETS							TAGS	STATUS
fg-efs	demo			<none>		arn:aws:iam::ACCOUNT_ID:role/eksctl-vietaws5-fargate-FargatePodExecutionRole-afuhdVvcwR4W	subnet-0c808fcc569ad2a4a,subnet-0a487fb8418801e8c	<none>	ACTIVE
```

# Create Fargate App

```
# Command
kubectl apply -f manifests/
```

# Verify

```
# Check Pod
kubectl get pods -n demo -owide

# Check Fargate node
kubectl get node

# Check Fargate config
kubectl -n demo describe pods home-deploy-xxx
// Output:
Annotations:          CapacityProvisioned: 0.25vCPU 0.5GB

# Check Log
kubectl -n demo exec -it home-deployment-6cdb6798bf-6rxgc -- tail -f /app-logs/out.txt

// Output
from Fargate Deployment. Hostname: home-deployment-6cdb6798bf-vg2ml
from Fargate Deployment. Hostname: home-deployment-6cdb6798bf-tgntv
from Fargate Deployment. Hostname: home-deployment-6cdb6798bf-6rxgc
from Fargate Deployment. Hostname: home-deployment-6cdb6798bf-vg2ml
from Fargate Deployment. Hostname: home-deployment-6cdb6798bf-tgntv
from Fargate Deployment. Hostname: home-deployment-6cdb6798bf-6rxgc
from Fargate Deployment. Hostname: home-deployment-6cdb6798bf-vg2ml

```

# Clean

```
# Delete Pods
kubectl delete -f manifests

# Delete Fargate profile
eksctl delete fargateprofile --cluster vietaws5 --name fg-efs --profile eks

# verify
kubectl get pods -n demo

kubectl get ns

eksctl get fargateprofile --cluster vietaws5 --profile eks
```
