#!/usr/bin/env bash
# Associate the secondary CIDR with the VPC and create the two pod subnets in it, or undo both.
# eksctl's vpc.extraCIDRs does NOT associate the CIDR (it only adds a control-plane security group
# rule), and eksctl cannot create subnets outside its own split, so this script owns both.
# They must be removed BEFORE `eksctl delete cluster`, otherwise the VPC (part of the eksctl
# CloudFormation stack) cannot be deleted.
#
# The pod subnets have no internet route (they use the VPC main route table, local routes only):
# pod traffic leaving the VPC is SNAT'd to the node's primary IP, which sits in a public subnet.
# They are deliberately NOT tagged kubernetes.io/role/cni, so only the ENIConfigs steer pods there.
#
# Values come from ../config.env. Usage: ./scripts/secondary-cidr.sh <create|delete>
# (called by up.sh / down.sh; uses AWS_PROFILE if set, else the default profile)
set -euo pipefail

# shellcheck source=SCRIPTDIR/../../lib/common.sh
. "$(dirname "$0")/../../lib/common.sh"
load_config
ACTION="${1:-}"

# "<AZ> <CIDR>" pairs. Plain list: macOS ships bash 3.2 (no associative arrays).
POD_SUBNETS=("$AZ_1 $POD_SUBNET_1_CIDR" "$AZ_2 $POD_SUBNET_2_CIDR")

association_field() { # <vpc-id> <field: State|AssociationId> -> value or "None"
  local query
  if [ "$2" = "State" ]; then
    query="Vpcs[0].CidrBlockAssociationSet[?CidrBlock=='${SECONDARY_CIDR}' && CidrBlockState.State!='disassociated'] | [0].CidrBlockState.State"
  else
    query="Vpcs[0].CidrBlockAssociationSet[?CidrBlock=='${SECONDARY_CIDR}' && CidrBlockState.State!='disassociated'] | [0].AssociationId"
  fi
  aws ec2 describe-vpcs --vpc-ids "$1" --query "$query" --output text
}

associate() { # <vpc-id>
  local vpc=$1 state _
  state=$(association_field "$vpc" State)
  if [ "$state" = "associated" ]; then
    echo "secondary CIDR $SECONDARY_CIDR already associated with $vpc"
    return 0
  fi
  if [ "$state" = "None" ]; then
    aws ec2 associate-vpc-cidr-block --vpc-id "$vpc" --cidr-block "$SECONDARY_CIDR" >/dev/null
    echo "associating secondary CIDR $SECONDARY_CIDR with $vpc"
  fi
  for _ in $(seq 1 30); do
    state=$(association_field "$vpc" State)
    case "$state" in
      associated) echo "secondary CIDR $SECONDARY_CIDR associated"; return 0 ;;
      failed | None)
        echo "association of $SECONDARY_CIDR with $vpc failed (state: $state). AWS restricts which" >&2
        echo "ranges can be added to a VPC; check the VPC console for the reason." >&2
        exit 1 ;;
    esac
    sleep 5
  done
  echo "timed out waiting for $SECONDARY_CIDR to become associated (state: $state)" >&2
  exit 1
}

subnet_id() { # <vpc-id> <cidr> -> subnet ID or "None"
  aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$1" "Name=cidr-block,Values=$2" \
    --query 'Subnets[0].SubnetId' --output text
}

create() {
  local vpc pair az cidr id
  vpc=$(vpc_id)
  associate "$vpc"
  for pair in "${POD_SUBNETS[@]}"; do
    az=${pair%% *}
    cidr=${pair##* }
    id=$(subnet_id "$vpc" "$cidr")
    if [ "$id" != "None" ]; then
      echo "pod subnet $cidr ($az) already exists: $id"
      continue
    fi
    id=$(aws ec2 create-subnet --vpc-id "$vpc" --availability-zone "$az" --cidr-block "$cidr" \
      --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${CLUSTER_NAME}-pods-${az}},{Key=${POD_SUBNET_TAG_KEY},Value=${POD_SUBNET_TAG_VALUE}}]" \
      --query 'Subnet.SubnetId' --output text)
    echo "created pod subnet $cidr ($az): $id"
  done
}

delete() {
  local vpc ids id in_use leftover eni assoc _
  if ! cluster_exists; then
    echo "cluster $CLUSTER_NAME not found, nothing to delete"
    return 0
  fi
  vpc=$(vpc_id)
  # Only subnets carrying our tag are touched.
  ids=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$vpc" "Name=tag:${POD_SUBNET_TAG_KEY},Values=${POD_SUBNET_TAG_VALUE}" \
    --query 'Subnets[].SubnetId' --output text)
  for id in $ids; do
    # Pod ENIs are deleted when their nodes terminate; wait for that (up to 10 minutes).
    for _ in $(seq 1 60); do
      in_use=$(aws ec2 describe-network-interfaces \
        --filters "Name=subnet-id,Values=$id" "Name=status,Values=in-use" \
        --query 'length(NetworkInterfaces)' --output text)
      [ "$in_use" = "0" ] && break
      echo "    $id: $in_use ENI(s) still in use, waiting..."
      sleep 10
    done
    # Detached (available) ENIs left by the VPC CNI would block the subnet deletion.
    leftover=$(aws ec2 describe-network-interfaces \
      --filters "Name=subnet-id,Values=$id" "Name=status,Values=available" \
      --query 'NetworkInterfaces[].NetworkInterfaceId' --output text)
    for eni in $leftover; do
      echo "    deleting leftover ENI $eni"
      aws ec2 delete-network-interface --network-interface-id "$eni"
    done
    aws ec2 delete-subnet --subnet-id "$id"
    echo "deleted pod subnet $id"
  done

  assoc=$(association_field "$vpc" AssociationId)
  if [ "$assoc" != "None" ]; then
    aws ec2 disassociate-vpc-cidr-block --association-id "$assoc" >/dev/null
    echo "disassociated secondary CIDR $SECONDARY_CIDR ($assoc)"
  fi
}

case "$ACTION" in
  create) create ;;
  delete) delete ;;
  *) echo "usage: $0 <create|delete>" >&2; exit 2 ;;
esac
