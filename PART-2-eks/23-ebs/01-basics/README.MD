# Highlights

1. Create IAM Policy for EBS
2. Associate IAM Policy to Worker Node
3. Install EBS CSI Driver

Read more:

- https://aws.amazon.com/blogs/storage/persistent-storage-for-kubernetes/

- https://github.com/kubernetes-sigs/aws-ebs-csi-driver

<img src="https://d2908q01vomqb2.cloudfront.net/e1822db470e60d090affd0956d743cb0e7cdf113/2022/10/28/3.Persistent-Volume-and-Persistent-Volume-Claim.png" alt='vietaws ebs eks' />

Scr: AWS Blog

```
# Check Installed Addons
aws eks list-addons --cluster-name  vietaws6 --profile eks
kubectl get csidriver ebs.csi.aws.com
```

Role name: `AmazonEKS_EBS_CSI_DriverRole`

```
# EBS Policy - CREATED
# Name: Amazon_EBS_CSI_Driver (AWS Managed Policy)

{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:AttachVolume",
        "ec2:CreateSnapshot",
        "ec2:CreateTags",
        "ec2:CreateVolume",
        "ec2:DeleteSnapshot",
        "ec2:DeleteTags",
        "ec2:DeleteVolume",
        "ec2:DescribeInstances",
        "ec2:DescribeSnapshots",
        "ec2:DescribeTags",
        "ec2:DescribeVolumes",
        "ec2:DetachVolume"
      ],
      "Resource": "*"
    }
  ]
}
```

# Deploy Amazon EBS CSI Driver

```
# Check OIDC on EKS
aws eks describe-cluster --name vietaws6 --profile eks --query "cluster.identity.oidc.issuer" --output text
# Output: https://oidc.eks.ap-southeast-1.amazonaws.com/id/OIDC_ID

# Check OIDC Provider on AWS
aws iam list-open-id-connect-providers --profile eks | grep OIDC_ID
#Output: "Arn": "arn:aws:iam::ACCOUNT_ID:oidc-provider/oidc.eks.ap-southeast-1.amazonaws.com/id/OIDC_ID"

# Create IAM Trust Policy
# Source: https://repost.aws/knowledge-center/eks-persistent-storage
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
          "oidc.eks.ap-southeast-1.amazonaws.com/id/OIDC_ID:aud": "sts.amazonaws.com",
          "oidc.eks.ap-southeast-1.amazonaws.com/id/OIDC_ID:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa"
        }
      }
    }
  ]
}
EOF

# Create IAM Role for EBS CSI
# Remember to change Role Name if it is existed
aws iam create-role \
 --role-name AmazonEKS_EBS_CSI_DriverRole6 \
 --assume-role-policy-document file://"trust-policy.json" --profile eks

# Attach AmazonEBSCSIDriverPolicy
aws iam attach-role-policy \
--policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
--role-name AmazonEKS_EBS_CSI_DriverRole6 --profile eks

# Check the EKS add-on tab on AWS Management Console
eksctl get addons --cluster vietaws6 --profile eks

# Approach 1 - install by using aws cli, eksctl (or Helm, Kustomize) - RECOMMENDED
aws eks create-addon \
--cluster-name vietaws6 \
--addon-name aws-ebs-csi-driver \
--service-account-role-arn arn:aws:iam::ACCOUNT_ID:role/AmazonEKS_EBS_CSI_DriverRole6 --profile eks

# Approach 2 - Using eksctl - https://docs.aws.amazon.com/eks/latest/userguide/managing-ebs-csi.html
eksctl create addon --name aws-ebs-csi-driver --cluster vietaws6 \
--service-account-role-arn arn:aws:iam::ACCOUNT_ID:role/AmazonEKS_EBS_CSI_DriverRole6 \
--force --profile eks


# Verify addon
1 - Go to AWS Management console. You will see the new Add-on and attached iam role
2 - eksctl get addons --cluster vietaws5 --profile eks # https://eksctl.io/usage/addons/
3 - kubectl get pods -n kube-system
4 - aws eks list-addons --cluster-name  vietaws5 --profile eks
5 - kubectl get csidriver ebs.csi.aws.com


# Approach 3 (install by using manifest)
# Deploy EBS CSI Driver
kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=master"

# Verify ebs-csi pods running
kubectl get pods -n kube-system

kubectl get all -l app.kubernetes.io/name=aws-ebs-csi-driver -n kube-system

```

# Deploy App

```
# Github: https://github.com/kubernetes-sigs/aws-ebs-csi-driver/tree/master/examples/kubernetes/dynamic-provisioning

# Create Storage Class & PVC
kubectl apply -f manifests

# List Storage Classes
kubectl get sc

# List PVC
kubectl get pvc

# List PV
kubectl get pv

# Verify App
kubectl exec -it app -- sh
cat /data/out.txt

# Update storage
Edit pvc.yaml 4Gi to 5Gi and apply will be failed.
kubectl apply -f manifests
```

# Clean Up

```
# Delete
kubectl delete -f manifests
```
