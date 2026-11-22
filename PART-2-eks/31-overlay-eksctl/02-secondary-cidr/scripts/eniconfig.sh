#!/usr/bin/env bash
# Create one ENIConfig per AZ (named after the AZ, matching ENI_CONFIG_LABEL_DEF=topology.kubernetes.io/zone).
# Pod ENIs use the pod subnets in the secondary CIDR and the cluster security group.
# The ENIConfig CRD comes from the vpc-cni add-on.
# Values come from ../config.env. Usage: ./scripts/eniconfig.sh
# (called by up.sh; uses AWS_PROFILE if set, else the default profile)
set -euo pipefail

# shellcheck source=SCRIPTDIR/../../lib/common.sh
. "$(dirname "$0")/../../lib/common.sh"
load_config

VPC_ID=$(vpc_id)
CLUSTER_SG=$(aws eks describe-cluster --name "$CLUSTER_NAME" \
  --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)

for pair in "$AZ_1 $POD_SUBNET_1_CIDR" "$AZ_2 $POD_SUBNET_2_CIDR"; do
  az=${pair%% *}
  cidr=${pair##* }
  subnet=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=cidr-block,Values=$cidr" \
    --query 'Subnets[0].SubnetId' --output text)
  [ -n "$subnet" ] && [ "$subnet" != "None" ] ||
    { echo "pod subnet $cidr not found in $VPC_ID (run ./scripts/secondary-cidr.sh create)" >&2; exit 1; }
  kubectl apply -f - <<YAML
apiVersion: crd.k8s.amazonaws.com/v1alpha1
kind: ENIConfig
metadata:
  name: $az
spec:
  subnet: $subnet
  securityGroups:
    - $CLUSTER_SG
YAML
done
kubectl get eniconfig
