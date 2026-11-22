#!/usr/bin/env bash
# Cost report for the nodes Karpenter launched: capacity type, price now, and what the same nodes would cost On-Demand.
# Read-only. Needs: kubectl, aws, jq, awk. IAM: ec2:DescribeSpotPriceHistory and pricing:GetProducts.
#
# Usage: ./scripts/cost-report.sh [--region=REGION] [--profile=AWS_PROFILE]
# Region default: AWS_REGION, otherwise ap-southeast-1. Prices are USD per hour, Linux, shared tenancy.
set -euo pipefail

REGION="${AWS_REGION:-ap-southeast-1}"
for arg in "$@"; do
  case "$arg" in
    --region=*) REGION="${arg#*=}" ;;
    --profile=*) export AWS_PROFILE="${arg#*=}" ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option '$arg' (use --help)" >&2; exit 1 ;;
  esac
done
[[ "$REGION" =~ ^[a-z]{2}(-[a-z]+)+-[0-9]$ ]] || { echo "region '$REGION' is not valid" >&2; exit 1; }
for tool in kubectl aws jq awk; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 1; }
done

on_demand_price() {  # instance type -> USD per hour (Pricing API is only served from us-east-1)
  aws pricing get-products --region us-east-1 --service-code AmazonEC2 --max-results 1 \
    --filters "Type=TERM_MATCH,Field=instanceType,Value=$1" "Type=TERM_MATCH,Field=regionCode,Value=$REGION" \
              "Type=TERM_MATCH,Field=operatingSystem,Value=Linux" "Type=TERM_MATCH,Field=tenancy,Value=Shared" \
              "Type=TERM_MATCH,Field=preInstalledSw,Value=NA" "Type=TERM_MATCH,Field=capacitystatus,Value=Used" \
    --query 'PriceList[0]' --output text |
    jq -r '.terms.OnDemand | to_entries[0].value.priceDimensions | to_entries[0].value.pricePerUnit.USD'
}
spot_price() {  # instance type, zone -> USD per hour (latest price)
  aws ec2 describe-spot-price-history --region "$REGION" --instance-types "$1" --availability-zone "$2" \
    --product-descriptions "Linux/UNIX" --start-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --query 'SpotPriceHistory[0].SpotPrice' --output text
}

NODES="$(kubectl get nodes -l karpenter.sh/nodepool -o json |
  jq -r '.items[] | [.metadata.name, .metadata.labels["node.kubernetes.io/instance-type"], .metadata.labels["karpenter.sh/capacity-type"], .metadata.labels["topology.kubernetes.io/zone"], .metadata.labels["kubernetes.io/arch"]] | @tsv')"
[ -n "$NODES" ] || { echo "No Karpenter nodes found. Scale a workload first (for example kubectl scale deployment web --replicas 4)." >&2; exit 1; }

printf '%-34s %-12s %-6s %-6s %-15s %10s %12s\n' NODE TYPE ARCH CAPACITY ZONE NOW_USD/H ONDEMAND_USD/H
TOTAL_NOW=0; TOTAL_OD=0
while IFS=$'\t' read -r name type cap zone arch; do
  od="$(on_demand_price "$type")"
  if [ "$cap" = spot ]; then now="$(spot_price "$type" "$zone")"; else now="$od"; fi
  printf '%-34s %-12s %-6s %-6s %-15s %10.4f %12.4f\n' "$name" "$type" "$arch" "$cap" "$zone" "$now" "$od"
  TOTAL_NOW="$(awk -v a="$TOTAL_NOW" -v b="$now" 'BEGIN{print a+b}')"
  TOTAL_OD="$(awk -v a="$TOTAL_OD" -v b="$od" 'BEGIN{print a+b}')"
done <<<"$NODES"

awk -v now="$TOTAL_NOW" -v od="$TOTAL_OD" 'BEGIN{
  printf "\nTotal now: $%.4f/hour   same nodes On-Demand: $%.4f/hour   saving: $%.4f/hour (%.0f%%)\n", now, od, od-now, (od>0 ? (od-now)/od*100 : 0)
  printf "Per 730-hour month: $%.2f now vs $%.2f On-Demand\n", now*730, od*730 }'
echo "Compare with the managed node group: kubectl get nodes -L node.kubernetes.io/instance-type,karpenter.sh/capacity-type"
