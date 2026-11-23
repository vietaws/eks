#!/usr/bin/env bash
# Hourly burn rate and window cost of the three demo clusters, from what is running RIGHT NOW.
# Prices come from the AWS Price List API (us-east-1 endpoint), never from constants in this script. When the API does not
# return a price, set the matching variable from the pricing pages and the table stays complete:
#   EC2_HOURLY_<type with . replaced by _>  e.g. EC2_HOURLY_t9g_medium=0.0xx
#   EKS_CLUSTER_HOURLY, AUTO_FEE_HOURLY (per instance-hour, depends on the instance type), NAT_HOURLY, NLB_HOURLY
# Pricing pages: https://aws.amazon.com/eks/pricing/  https://aws.amazon.com/ec2/pricing/on-demand/
#                https://aws.amazon.com/vpc/pricing/  https://aws.amazon.com/elasticloadbalancing/pricing/
#
# Usage: ./scripts/cost.sh [window-hours]        e.g. ./scripts/cost.sh 3    (default 1). Needs aws, jq, awk.
# Assumptions printed in the output: 1 NLB per cluster (the test Service), NAT gateways counted from the eksctl tag.
set -uo pipefail
HOURS="${1:-1}"
AWS_REGION="${AWS_REGION:-ap-southeast-1}"
[[ "$HOURS" =~ ^[0-9]+(\.[0-9]+)?$ ]] || { echo "window-hours must be a number" >&2; exit 1; }
for tool in aws jq awk; do command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 1; }; done
CLUSTERS=(upg-mng upg-karp upg-auto)
MISSING=()

pricing() { aws pricing get-products --region us-east-1 --max-results 100 "$@" --output json 2>/dev/null; }
first_usd() { jq -r '[.PriceList[]|fromjson|.terms.OnDemand[]?.priceDimensions[]?.pricePerUnit.USD|tonumber|select(.>0)]|min // empty'; }

ec2_price() { # <instance-type>
  local var="EC2_HOURLY_${1//./_}"; [ -n "${!var:-}" ] && { echo "${!var}"; return; }
  pricing --service-code AmazonEC2 --filters "Type=TERM_MATCH,Field=regionCode,Value=$AWS_REGION" \
    "Type=TERM_MATCH,Field=instanceType,Value=$1" "Type=TERM_MATCH,Field=operatingSystem,Value=Linux" \
    "Type=TERM_MATCH,Field=tenancy,Value=Shared" "Type=TERM_MATCH,Field=preInstalledSw,Value=NA" \
    "Type=TERM_MATCH,Field=capacitystatus,Value=Used" | first_usd
}
eks_cluster_price() {
  [ -n "${EKS_CLUSTER_HOURLY:-}" ] && { echo "$EKS_CLUSTER_HOURLY"; return; }
  # standard support is the cheapest per-cluster rate (extended support costs more)
  pricing --service-code AmazonEKS --filters "Type=TERM_MATCH,Field=regionCode,Value=$AWS_REGION" |
    jq -r '[.PriceList[]|fromjson|select(.product.attributes.usagetype|test("perCluster"))|.terms.OnDemand[]?.priceDimensions[]?.pricePerUnit.USD|tonumber|select(.>0)]|min // empty'
}
auto_fee() { # <instance-type>
  [ -n "${AUTO_FEE_HOURLY:-}" ] && { echo "$AUTO_FEE_HOURLY"; return; }
  pricing --service-code AmazonEKS --filters "Type=TERM_MATCH,Field=regionCode,Value=$AWS_REGION" |
    jq -r --arg t "$1" '[.PriceList[]|fromjson|select((.product.attributes.usagetype|test("Auto"))and(.product.attributes.instanceType==$t))|.terms.OnDemand[]?.priceDimensions[]?.pricePerUnit.USD|tonumber|select(.>0)]|min // empty'
}
nat_price() {
  [ -n "${NAT_HOURLY:-}" ] && { echo "$NAT_HOURLY"; return; }
  pricing --service-code AmazonEC2 --filters "Type=TERM_MATCH,Field=regionCode,Value=$AWS_REGION" \
    "Type=TERM_MATCH,Field=productFamily,Value=NAT Gateway" | jq -r '[.PriceList[]|fromjson|select(.product.attributes.usagetype|test("NatGateway-Hours"))|.terms.OnDemand[]?.priceDimensions[]?.pricePerUnit.USD|tonumber|select(.>0)]|min // empty'
}
nlb_price() {
  [ -n "${NLB_HOURLY:-}" ] && { echo "$NLB_HOURLY"; return; }
  pricing --service-code AWSELB --filters "Type=TERM_MATCH,Field=regionCode,Value=$AWS_REGION" \
    "Type=TERM_MATCH,Field=productFamily,Value=Load Balancer-Network" | jq -r '[.PriceList[]|fromjson|select(.product.attributes.usagetype|test("LoadBalancerUsage"))|.terms.OnDemand[]?.priceDimensions[]?.pricePerUnit.USD|tonumber|select(.>0)]|min // empty'
}

CP="$(eks_cluster_price)"; NAT="$(nat_price)"; NLB="$(nlb_price)"
[ -n "$CP" ]  || MISSING+=("EKS_CLUSTER_HOURLY")
[ -n "$NAT" ] || MISSING+=("NAT_HOURLY")
[ -n "$NLB" ] || MISSING+=("NLB_HOURLY")

printf '\n%-10s %-6s %-12s %9s %9s %9s %9s %9s %10s %12s\n' cluster nodes type ec2/h auto-fee/h ctrl/h nat/h nlb/h '$/hour' "\$/${HOURS}h"
GRAND=0
for c in "${CLUSTERS[@]}"; do
  TYPES="$({ aws ec2 describe-instances --region "$AWS_REGION" --filters "Name=instance-state-name,Values=running" "Name=tag:eks:cluster-name,Values=$c" --query 'Reservations[].Instances[].InstanceType' --output text
             aws ec2 describe-instances --region "$AWS_REGION" --filters "Name=instance-state-name,Values=running" "Name=tag:eks:eks-cluster-name,Values=$c" --query 'Reservations[].Instances[].InstanceType' --output text; } 2>/dev/null | tr '\t' '\n' | sed '/^$/d')"
  if [ -z "$TYPES" ]; then printf '%-10s %-6s (no running nodes found, cluster missing or tags differ)\n' "$c" 0; continue; fi
  NN="$(wc -l <<<"$TYPES" | tr -d ' ')"
  NATS="$(aws ec2 describe-nat-gateways --region "$AWS_REGION" --filter "Name=tag:alpha.eksctl.io/cluster-name,Values=$c" "Name=state,Values=available" --query 'length(NatGateways)' --output text 2>/dev/null)"; NATS="${NATS:-1}"
  EC2_SUM=0; AUTO_SUM=0
  for t in $(sort -u <<<"$TYPES"); do
    n="$(grep -cx "$t" <<<"$TYPES")"; p="$(ec2_price "$t")"
    [ -n "$p" ] || { MISSING+=("EC2_HOURLY_${t//./_}"); p=0; }
    EC2_SUM="$(awk -v a="$EC2_SUM" -v n="$n" -v p="$p" 'BEGIN{print a+n*p}')"
    if [ "$c" = upg-auto ]; then
      f="$(auto_fee "$t")"; [ -n "$f" ] || { MISSING+=("AUTO_FEE_HOURLY($t)"); f=0; }
      AUTO_SUM="$(awk -v a="$AUTO_SUM" -v n="$n" -v p="$f" 'BEGIN{print a+n*p}')"
    fi
  done
  HOURLY="$(awk -v e="$EC2_SUM" -v a="$AUTO_SUM" -v cp="${CP:-0}" -v nat="${NAT:-0}" -v ns="$NATS" -v nlb="${NLB:-0}" 'BEGIN{print e+a+cp+nat*ns+nlb}')"
  WIN="$(awk -v h="$HOURLY" -v w="$HOURS" 'BEGIN{print h*w}')"
  GRAND="$(awk -v g="$GRAND" -v w="$WIN" 'BEGIN{print g+w}')"
  printf '%-10s %-6s %-12s %9.4f %9.4f %9.4f %9.4f %9.4f %10.4f %12.4f\n' "$c" "$NN" "$(sort -u <<<"$TYPES" | paste -sd, -)" "$EC2_SUM" "$AUTO_SUM" "${CP:-0}" "$(awk -v n="${NAT:-0}" -v s="$NATS" 'BEGIN{print n*s}')" "${NLB:-0}" "$HOURLY" "$WIN"
done
echo
printf 'Total for %sh: $%.4f  (EC2 on-demand, Auto Mode fee, control plane, NAT hours, 1 NLB per cluster; data transfer and EBS not included)\n' "$HOURS" "$GRAND"
if [ "${#MISSING[@]}" -gt 0 ]; then
  echo "INCOMPLETE: no price found for: ${MISSING[*]}"
  echo "Look them up on the pricing pages in the header, export the variables above and run again."
fi
