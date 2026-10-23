# 22.01.04 — Install Karpenter

> 📗 Official: https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/
>
> ✅ Use a **Karpenter v1.x** release (the API `karpenter.sh/v1` is GA) and the
> **AL2023** AMI family. The `0.3x` releases + `v1beta1` API + `AL2` family shown
> in older tutorials are deprecated.

## 1 — Configure environment
```bash
export CLUSTER_NAME="eksdemo"
# Pick a Kubernetes version EKS currently supports (e.g. one of the latest).
export K8S_VERSION="1.31"

export KARPENTER_NAMESPACE="kube-system"
# Use the latest Karpenter v1.x release tag:
export KARPENTER_VERSION="1.x.y"

export AWS_PARTITION="aws"
export AWS_DEFAULT_REGION="ap-southeast-1"
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text --profile eks)"
export TEMPOUT="$(mktemp)"

# AL2023 optimized AMIs (AL2 is end-of-support):
export ARM_AMI_ID="$(aws ssm get-parameter --name /aws/service/eks/optimized-ami/${K8S_VERSION}/amazon-linux-2023/arm64/standard/recommended/image_id --query Parameter.Value --output text)"
export AMD_AMI_ID="$(aws ssm get-parameter --name /aws/service/eks/optimized-ami/${K8S_VERSION}/amazon-linux-2023/x86_64/standard/recommended/image_id --query Parameter.Value --output text)"
```

## 2 — Create the cluster (with Pod Identity for Karpenter)
```bash
curl -fsSL https://raw.githubusercontent.com/aws/karpenter-provider-aws/v"${KARPENTER_VERSION}"/website/content/en/preview/getting-started/getting-started-with-karpenter/cloudformation.yaml > "${TEMPOUT}" \
&& aws cloudformation deploy \
  --stack-name "Karpenter-${CLUSTER_NAME}" \
  --template-file "${TEMPOUT}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "ClusterName=${CLUSTER_NAME}"

eksctl create cluster -f - <<EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: ${CLUSTER_NAME}
  region: ${AWS_DEFAULT_REGION}
  version: "${K8S_VERSION}"
  tags:
    karpenter.sh/discovery: ${CLUSTER_NAME}
iam:
  withOIDC: true
  podIdentityAssociations:          # modern auth (preferred over IRSA)
  - namespace: "${KARPENTER_NAMESPACE}"
    serviceAccountName: karpenter
    roleName: ${CLUSTER_NAME}-karpenter
    permissionPolicyARNs:
    - arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerPolicy-${CLUSTER_NAME}
iamIdentityMappings:
- arn: "arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:role/KarpenterNodeRole-${CLUSTER_NAME}"
  username: system:node:{{EC2PrivateDNSName}}
  groups:
  - system:bootstrappers
  - system:nodes
managedNodeGroups:
- instanceType: t3.medium       # small bootstrap node group for Karpenter itself
  amiFamily: AL2023
  name: ${CLUSTER_NAME}-ng
  desiredCapacity: 2
  minSize: 1
  maxSize: 3
addons:
- name: eks-pod-identity-agent
EOF
```

## 3 — Spot service-linked role (one-time per account)
```bash
aws iam create-service-linked-role --aws-service-name spot.amazonaws.com || true
```

## 4 — Install Karpenter via Helm
```bash
helm registry logout public.ecr.aws || true
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version "${KARPENTER_VERSION}" \
  --namespace "${KARPENTER_NAMESPACE}" --create-namespace \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.interruptionQueue=${CLUSTER_NAME}" \
  --set controller.resources.requests.cpu=1 \
  --set controller.resources.requests.memory=1Gi \
  --set controller.resources.limits.cpu=1 \
  --set controller.resources.limits.memory=1Gi \
  --wait
```

## 5 — Cleanup
```bash
helm uninstall karpenter -n kube-system
eksctl delete addon --cluster ${CLUSTER_NAME} --name eks-pod-identity-agent
eksctl delete cluster --name ${CLUSTER_NAME}
aws cloudformation delete-stack --stack-name "Karpenter-${CLUSTER_NAME}"
```

## 📝 Notes
- Karpenter is **not** tied to the cluster's Kubernetes version (unlike Cluster
  Autoscaler) — upgrade it independently.
- 🔐 `AWS_ACCOUNT_ID` is resolved at runtime via `sts get-caller-identity`; never
  hardcode a real account ID in these files.
