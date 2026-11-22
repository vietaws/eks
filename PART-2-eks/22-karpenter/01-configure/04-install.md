# 22.01.04 — Install Karpenter

> 📗 Official: https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/
>
> ✅ **Karpenter 1.15.x** is the line that supports **Kubernetes 1.37** (see the
> [compatibility matrix](https://karpenter.sh/docs/upgrading/compatibility/)). It uses the stable
> `karpenter.sh/v1` API, the **AL2023** AMI family and **EKS Pod Identity**. The `0.3x` releases,
> the `v1beta1` API and the `AL2` AMI family from older tutorials are deprecated.

## 1 — Create the cluster (shared script)
The cluster is created by `02-create-eks-cluster`. It already has OIDC, the Pod Identity agent,
the `karpenter.sh/discovery` tag on subnets and security groups, and a public managed node group
that hosts the Karpenter controller. Nothing here repeats that.

```bash
export AWS_REGION=ap-southeast-1 CLUSTER_NAME=eksdemo
(cd ../02-create-eks-cluster && ./scripts/up.sh --mode=standard)    # about 15-20 min
```

## 2 — Install Karpenter (script)
```bash
./scripts/install-karpenter.sh        # from 22-karpenter/, about 5 min
```

What the script does, in order:

| # | Step | Why |
|---|------|-----|
| 1 | `aws cloudformation deploy` of the template pinned to the Karpenter release tag | Creates `KarpenterNodeRole-<cluster>`, **six** controller policies (`NodeLifecycle`, `IAMIntegration`, `EKSIntegration`, `Interruption`, `ResourceDiscovery`, `ZonalShift`), the SQS interruption queue and the EventBridge rules |
| 2 | `aws iam create-service-linked-role --aws-service-name spot.amazonaws.com` | One time per account, needed for Spot |
| 3 | `eksctl create podidentityassociation` for `kube-system/karpenter` | Gives the controller its IAM role (Pod Identity, no IRSA annotation) |
| 4 | `eksctl create iamidentitymapping` for the node role | Lets Karpenter-launched nodes join the cluster |
| 5 | `helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter` | Installs the controller and CRDs |

> ⚠️ The old single `KarpenterControllerPolicy-<cluster>` policy used by earlier versions of this
> demo no longer exists in the 1.15 template. Attaching it fails with `NoSuchEntity`.

### Manual equivalent (to teach each step)
```bash
export KARPENTER_NAMESPACE="kube-system"
export KARPENTER_VERSION="1.15.3"
export AWS_PARTITION="aws"
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export TEMPOUT="$(mktemp)"

curl -fsSL "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${KARPENTER_VERSION}/website/content/en/preview/getting-started/getting-started-with-karpenter/cloudformation.yaml" > "${TEMPOUT}"
aws cloudformation deploy \
  --stack-name "Karpenter-${CLUSTER_NAME}" \
  --template-file "${TEMPOUT}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "ClusterName=${CLUSTER_NAME}"

aws iam create-service-linked-role --aws-service-name spot.amazonaws.com || true

P="arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:policy/KarpenterController"
eksctl create podidentityassociation --cluster "${CLUSTER_NAME}" \
  --namespace "${KARPENTER_NAMESPACE}" --service-account-name karpenter \
  --role-name "${CLUSTER_NAME}-karpenter" \
  --permission-policy-arns "${P}NodeLifecyclePolicy-${CLUSTER_NAME},${P}IAMIntegrationPolicy-${CLUSTER_NAME},${P}EKSIntegrationPolicy-${CLUSTER_NAME},${P}InterruptionPolicy-${CLUSTER_NAME},${P}ResourceDiscoveryPolicy-${CLUSTER_NAME},${P}ZonalShiftPolicy-${CLUSTER_NAME}"

eksctl create iamidentitymapping --cluster "${CLUSTER_NAME}" \
  --arn "arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:role/KarpenterNodeRole-${CLUSTER_NAME}" \
  --username 'system:node:{{EC2PrivateDNSName}}' \
  --group system:bootstrappers --group system:nodes

helm registry logout public.ecr.aws || true
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version "${KARPENTER_VERSION}" --namespace "${KARPENTER_NAMESPACE}" --create-namespace \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.interruptionQueue=${CLUSTER_NAME}" \
  --set controller.resources.requests.cpu=1 --set controller.resources.requests.memory=1Gi \
  --set controller.resources.limits.cpu=1 --set controller.resources.limits.memory=1Gi \
  --wait
```

## 🔍 Validation
```bash
helm list -n kube-system | grep karpenter
kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter     # 2 pods Running
kubectl get crd | grep -E 'karpenter'                                   # nodepools, nodeclaims, ec2nodeclasses
```

## ⬆️ Upgrading Karpenter later
Karpenter is **not** tied to the cluster's Kubernetes version the way Cluster Autoscaler is, but each
minor supports a fixed range of Kubernetes versions. Before you upgrade the cluster, check the
[compatibility matrix](https://karpenter.sh/docs/upgrading/compatibility/), upgrade Karpenter first if
needed, and re-run `helm upgrade --install` with the new `KARPENTER_VERSION`. Regular releases are supported
only until the next minor is published. For fewer upgrades pick an LTS release (see the same page).

## 🧹 Cleanup
```bash
# Removes NodePools + their nodes, the Helm release, launch templates, the CloudFormation stack and the cluster
(cd ../02-create-eks-cluster && ./scripts/down.sh --cluster-name=eksdemo)
```

## 📝 Notes
- 🔐 `AWS_ACCOUNT_ID` is resolved at runtime via `sts get-caller-identity`; never hardcode a real account ID.
- ⚠️ **Not tested against a live AWS account.** The script passes `shellcheck`; flags were checked against
  `eksctl` help and the v1.15.3 CloudFormation template. Report any difference.
- Optional from the official guide, left out to keep the demo short: `kubeSchedulerConfig` with
  `MostAllocated` scoring (packs pods tighter, helps consolidation) and the Zonal Shift integration.
