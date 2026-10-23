# Setup IAM Role & SA

```
# Create EFS IAM Poliy for EFS CSI Driver
curl -o iam-policy-example.json https://raw.githubusercontent.com/kubernetes-sigs/aws-efs-csi-driver/master/docs/iam-policy-example.json

# Create IAM Policy
aws iam create-policy \
    --policy-name AmazonEKS_EFS_CSI_Driver_Policy \
    --policy-document file://iam-policy-example.json \
    --profile eks

// Output
{
    "Policy": {
        "PolicyName": "AmazonEKS_EFS_CSI_Driver_Policy",
        "PolicyId": "ANPA4AQ6BIRYZE2U5BONK",
        "Arn": "arn:aws:iam::ACCOUNT_ID:policy/AmazonEKS_EFS_CSI_Driver_Policy",
        "Path": "/",
        "DefaultVersionId": "v1",
        "AttachmentCount": 0,
        "PermissionsBoundaryUsageCount": 0,
        "IsAttachable": true,
        "CreateDate": "2024-05-29T03:43:42+00:00",
        "UpdateDate": "2024-05-29T03:43:42+00:00"
    }
}

# Find OIDC for cluster
aws eks describe-cluster --name vietaws6 --query "cluster.identity.oidc.issuer" --output text --profile eks

// Output: https://oidc.eks.ap-southeast-1.amazonaws.com/id/OIDC_ID

# Create Trust Policy

- Region: ap-southeast-1
- Account ID: ACCOUNT_ID

cat <<EOF > trust-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/oidc.eks.ap-southeast-1.amazonaws.com/id/OIDC_ID"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.ap-southeast-1.amazonaws.com/id/OIDC_ID:sub": "system:serviceaccount:kube-system:efs-csi-controller-sa"
        }
      }
    }
  ]
}
EOF

# Create IAM Role
aws iam create-role \
  --role-name AmazonEKS_EFS_CSI_DriverRole6 \
  --assume-role-policy-document file://"trust-policy.json" \
  --profile eks

# Verify on IAM Console - User
🌈 For each cluster, you have to re-create AmazonEKS_EFS_CSI_DriverRole because of OIDC

# Attach IAM Policy to EFS IAM Role
aws iam attach-role-policy \
  --policy-arn arn:aws:iam::ACCOUNT_ID:policy/AmazonEKS_EFS_CSI_Driver_Policy \
  --role-name AmazonEKS_EFS_CSI_DriverRole6 \
  --profile eks
// Verify on AWS Console

# Download efs csi driver
kubectl kustomize "github.com/kubernetes-sigs/aws-efs-csi-driver/deploy/kubernetes/overlays/stable/?ref=master" > public-ecr-driver.yaml

# 🚨 Edit Role ARN for public-ecr-driver.yaml

annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT_ID:role/AmazonEKS_EFS_CSI_DriverRole6

# Apply IRSA for EFS
kubectl apply -f public-ecr-driver.yaml

// Output
serviceaccount/efs-csi-controller-sa created
serviceaccount/efs-csi-node-sa created
clusterrole.rbac.authorization.k8s.io/efs-csi-external-provisioner-role created
clusterrole.rbac.authorization.k8s.io/efs-csi-external-provisioner-role-describe-secrets created
clusterrole.rbac.authorization.k8s.io/efs-csi-node-role created
rolebinding.rbac.authorization.k8s.io/efs-csi-provisioner-binding-describe-secrets created
clusterrolebinding.rbac.authorization.k8s.io/efs-csi-node-binding created
clusterrolebinding.rbac.authorization.k8s.io/efs-csi-provisioner-binding created
deployment.apps/efs-csi-controller created
daemonset.apps/efs-csi-node created
csidriver.storage.k8s.io/efs.csi.aws.com configured

# If your cluster has Fargate, deploy below command

kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-efs-csi-driver/master/deploy/kubernetes/base/csidriver.yaml

# Check file size EFS

aws efs describe-file-systems \
    --file-system-id fs-0f5eecb0ee13c850b --profile eks

kubectl exec -it pods/efs-app -- sh


```
