#!/usr/bin/env bash
# Constant-rate load with a percentile and status-code summary, using `hey` (brew install hey).
# Use it next to probe.sh: probe.sh catches short gaps, load.sh shows errors and p99 latency under real traffic.
#
# Usage: ./scripts/load.sh <url> [duration] [requests-per-second]      e.g. ./scripts/load.sh http://<nlb-hostname> 30m 50
set -euo pipefail
URL="${1:-}"; DURATION="${2:-30m}"; RPS="${3:-50}"
[[ "$URL" =~ ^https?://[A-Za-z0-9._:/-]+$ ]] || { echo "usage: $0 <url> [duration] [rps]" >&2; exit 1; }
[[ "$DURATION" =~ ^[0-9]+[smh]$ && "$RPS" =~ ^[0-9]+$ ]] || { echo "duration like 30m, rps a number" >&2; exit 1; }
command -v hey >/dev/null || { echo "missing tool: hey (brew install hey)" >&2; exit 1; }
WORKERS=10
echo "Sending about $RPS requests/s for $DURATION with $WORKERS workers"
hey -z "$DURATION" -c "$WORKERS" -q $((RPS / WORKERS)) -t 2 "$URL"
