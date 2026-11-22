#!/usr/bin/env bash
# Fail if the planned VPC CIDRs overlap any VPC CIDR (primary or secondary) in this account and region.
# AWS refuses a VPC peering connection when ANY CIDR of the two VPCs overlaps, even if you only want to
# use the non-overlapping ones: https://docs.aws.amazon.com/vpc/latest/peering/vpc-peering-basics.html
# This only sees the current account and region. Check peers in other accounts, regions or on-premises yourself.
#
# Usage: ./scripts/preflight-cidr.sh [main-cidr] [secondary-cidr]   (defaults: VPC_CIDR and SECONDARY_CIDR
# from ../config.env; uses AWS_PROFILE if set, else the default profile)
# Set ALLOW_OVERLAP=1 to downgrade failures to warnings (for example when you never peer this VPC).
# Set VPCS_JSON_FILE=<file> to read `aws ec2 describe-vpcs` output from a file (used for offline tests).
set -euo pipefail

# shellcheck source=SCRIPTDIR/../../lib/common.sh
. "$(dirname "$0")/../../lib/common.sh"
load_config # profile: inherited from the caller (AWS_PROFILE) or the default profile
MAIN_CIDR="${1:-$VPC_CIDR}"
SECONDARY_CIDR="${2:-$SECONDARY_CIDR}"

command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }

if [ -n "${VPCS_JSON_FILE:-}" ]; then
  VPCS_JSON=$(cat "$VPCS_JSON_FILE")
else
  VPCS_JSON=$(aws ec2 describe-vpcs --output json)
fi

STATUS=0
printf '%s' "$VPCS_JSON" | python3 -c '
import ipaddress, json, sys

main, secondary = sys.argv[1], sys.argv[2]
planned = [("main", main), ("secondary", secondary)]
clash = False
for vpc in json.load(sys.stdin)["Vpcs"]:
    vpc_id = vpc["VpcId"]
    name = next((t["Value"] for t in vpc.get("Tags", []) if t["Key"] == "Name"), "-")
    for assoc in vpc.get("CidrBlockAssociationSet", []):
        other = assoc["CidrBlock"]
        for label, cidr in planned:
            if ipaddress.ip_network(cidr).overlaps(ipaddress.ip_network(other)):
                print("OVERLAP: planned %s CIDR %s overlaps %s (%s, %s)" % (label, cidr, other, vpc_id, name))
                clash = True
if not clash:
    print("OK: %s and %s overlap no VPC CIDR in this account/region" % (main, secondary))
sys.exit(1 if clash else 0)
' "$MAIN_CIDR" "$SECONDARY_CIDR" || STATUS=$?

if [ "$STATUS" -ne 0 ]; then
  if [ "${ALLOW_OVERLAP:-0}" = "1" ]; then
    echo "WARNING: overlap ignored (ALLOW_OVERLAP=1). Peering with the VPCs above will be impossible." >&2
    exit 0
  fi
  echo "Pick CIDRs that no peer VPC uses (edit config.env), or set ALLOW_OVERLAP=1." >&2
  exit 1
fi
