#!/usr/bin/env bash
# Availability probe. Requests the URL every INTERVAL seconds, logs every request to a CSV and prints a summary on
# Ctrl-C: total/failed requests, the longest run of consecutive failures, and latency p50/p99.
# Start it BEFORE the upgrade and leave it running until the last node is replaced.
# A request fails on any status other than 200 or when it takes longer than TIMEOUT seconds.
#
# Usage: ./scripts/probe.sh <url> [interval-seconds] [timeout-seconds]    e.g. ./scripts/probe.sh http://<nlb-hostname> 0.2 1
# Output: probe-<cluster>-<time>.csv in the current directory (columns: time,http_code,seconds)
set -uo pipefail

URL="${1:-}"
INTERVAL="${2:-0.2}"
TIMEOUT="${3:-1}"
[[ "$URL" =~ ^https?://[A-Za-z0-9._:/-]+$ ]] || { echo "usage: $0 <http(s)://host[:port][/path]> [interval] [timeout]" >&2; exit 1; }
[[ "$INTERVAL" =~ ^[0-9]+(\.[0-9]+)?$ && "$TIMEOUT" =~ ^[0-9]+(\.[0-9]+)?$ ]] || { echo "interval and timeout must be numbers" >&2; exit 1; }
command -v curl >/dev/null || { echo "missing tool: curl" >&2; exit 1; }

CSV="probe-${CLUSTER_NAME:-run}-$(date -u +%Y%m%dT%H%M%S).csv"
echo "time,http_code,seconds" >"$CSV"
OK=0; FAIL=0; STREAK=0; MAXSTREAK=0; STREAK_START=0; MAXSECS=0; FIRST_FAIL=""; LAST_FAIL=""

summary() {
  echo; echo "---- probe summary ($CSV) ----"
  echo "requests: $((OK + FAIL))  ok: $OK  failed: $FAIL"
  if [ "$FAIL" -gt 0 ]; then
    echo "first failure: $FIRST_FAIL   last failure: $LAST_FAIL"
    echo "longest outage: $MAXSTREAK consecutive failed requests, about ${MAXSECS}s wall clock"
  else
    echo "no failed requests: zero downtime observed"
  fi
  awk -F, 'NR>1 && $2==200 {print $3}' "$CSV" | sort -n | awk '{a[NR]=$1} END{ if (NR) printf "latency ok requests: p50=%.3fs p99=%.3fs max=%.3fs\n", a[int((NR+1)/2)], a[int(NR*0.99)>0?int(NR*0.99):1], a[NR] }'
}
trap 'summary; exit 0' INT TERM

echo "Probing $URL every ${INTERVAL}s, timeout ${TIMEOUT}s, log $CSV (Ctrl-C to stop)"
LAST_PRINT=$SECONDS
while true; do
  OUT="$(curl -s -o /dev/null -m "$TIMEOUT" -w '%{http_code} %{time_total}' "$URL" || true)"
  CODE="${OUT%% *}"; SECS="${OUT##* }"; NOW="$(date -u +%H:%M:%S)"
  echo "$NOW,${CODE:-000},${SECS:-0}" >>"$CSV"
  if [ "$CODE" = 200 ]; then
    OK=$((OK + 1)); STREAK=0
  else
    FAIL=$((FAIL + 1)); STREAK=$((STREAK + 1))
    EPOCH="$(date +%s)"; [ "$STREAK" -eq 1 ] && STREAK_START=$EPOCH
    [ $((EPOCH - STREAK_START + 1)) -gt "$MAXSECS" ] && MAXSECS=$((EPOCH - STREAK_START + 1))
    [ "$STREAK" -gt "$MAXSTREAK" ] && MAXSTREAK=$STREAK
    [ -n "$FIRST_FAIL" ] || FIRST_FAIL=$NOW
    LAST_FAIL=$NOW
    echo "$NOW FAIL http_code=${CODE:-000}"
  fi
  if [ $((SECONDS - LAST_PRINT)) -ge 10 ]; then
    echo "$NOW ok=$OK fail=$FAIL"; LAST_PRINT=$SECONDS
  fi
  sleep "$INTERVAL"
done
