#!/usr/bin/env bash
# Print the Karpenter AMI alias for an EKS-optimized AL2023 release that exists for a Kubernetes version.
# Pinned aliases are resolved per Kubernetes version, so after a control plane upgrade you must move the alias
# to a release that exists for the NEW version.
#
# Usage: ./scripts/ami-release.sh <k8s-version> [latest|list]      e.g. ./scripts/ami-release.sh 1.36 latest
set -euo pipefail
K8S="${1:?usage: $0 <k8s-version> [latest|list]}"
MODE="${2:-latest}"
AWS_REGION="${AWS_REGION:-ap-southeast-1}"
[[ "$K8S" =~ ^1\.[0-9]{2}$ ]] || { echo "k8s-version must look like 1.37" >&2; exit 1; }
ARCH="arm64" # t9g / t4g are Graviton; use x86_64 for Intel/AMD
if [ "$MODE" = list ]; then
  aws ssm get-parameters-by-path --region "$AWS_REGION" --recursive \
    --path "/aws/service/eks/optimized-ami/${K8S}/amazon-linux-2023/${ARCH}/standard/" --query 'Parameters[].Name' --output text |
    tr '\t' '\n' | grep -v recommended | awk -F/ '{print $NF}' | sort -u
  exit 0
fi
AMI_ID="$(aws ssm get-parameter --region "$AWS_REGION" --query Parameter.Value --output text \
  --name "/aws/service/eks/optimized-ami/${K8S}/amazon-linux-2023/${ARCH}/standard/recommended/image_id")"
NAME="$(aws ec2 describe-images --region "$AWS_REGION" --image-ids "$AMI_ID" --query 'Images[0].Name' --output text)"
# image name ends with the release, for example amazon-eks-node-al2023-arm64-standard-1.36-v20261015
REL="$(printf '%s' "$NAME" | sed -E 's/.*-(v[0-9]{8})$/\1/')"
[[ "$REL" =~ ^v[0-9]{8}$ ]] || { echo "could not read the release from image name '$NAME'" >&2; exit 1; }
echo "al2023@${REL}"
