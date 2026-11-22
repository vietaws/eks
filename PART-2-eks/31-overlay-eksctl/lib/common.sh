# shellcheck shell=bash
# Shared helpers for the 31-overlay-eksctl demos. Source it from a script in <demo>/scripts/:
#   . "$(dirname "$0")/../../lib/common.sh"
#
# Sets:  DEMO_DIR    the demo folder (parent of the calling script's folder)
#        RENDER_DIR  $DEMO_DIR/.rendered, where the *.yaml templates are rendered

DEMO_DIR=$(cd "$(dirname "${BASH_SOURCE[1]:-$0}")/.." && pwd)
RENDER_DIR="$DEMO_DIR/.rendered"

# Load <demo>/config.env (the single source of truth) and export every value, so the
# templates and child scripts see them.
load_config() {
  local cfg="$DEMO_DIR/config.env"
  [ -f "$cfg" ] || { echo "config file not found: $cfg" >&2; exit 1; }
  set -a
  # shellcheck source=/dev/null
  . "$cfg"
  set +a
  export AWS_REGION="$REGION"
}

# Optional AWS profile argument. Without it the default credential chain is used
# (AWS_PROFILE if it is set, otherwise the [default] profile). Prints the account in use.
use_profile() {
  if [ -n "${1:-}" ]; then
    export AWS_PROFILE="$1"
  fi
  ACCOUNT=$(aws sts get-caller-identity --query Account --output text) ||
    { echo "AWS credentials not usable for profile '${AWS_PROFILE:-default}'" >&2; exit 1; }
  echo "AWS profile: ${AWS_PROFILE:-default}  account: $ACCOUNT  region: $AWS_REGION  cluster: $CLUSTER_NAME"
}

require_tools() {
  local tool
  for tool in "$@"; do
    command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 1; }
  done
}

# Render every *.yaml under the demo folder (except .rendered/) into .rendered/, replacing
# ${VAR} placeholders with values from config.env. Fails on any placeholder without a value.
render() {
  python3 - "$DEMO_DIR" "$RENDER_DIR" <<'PY'
import os, pathlib, shutil, string, sys

src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
if dst.exists():
    shutil.rmtree(dst)  # only ever the demo's own .rendered/ folder
errors = []
for path in sorted(src.rglob("*.yaml")):
    rel = path.relative_to(src)
    if rel.parts[0] == ".rendered":
        continue
    try:
        text = string.Template(path.read_text()).substitute(os.environ)
    except KeyError as e:
        errors.append(f"{rel}: no value for ${{{e.args[0]}}} in config.env")
        continue
    except ValueError as e:
        errors.append(f"{rel}: {e}")
        continue
    out = dst / rel
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(text)
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
PY
  echo "Rendered templates into ${RENDER_DIR#"$DEMO_DIR"/}/"
}

# Sanity-check CIDRs from config.env before touching AWS.
# Arguments: rules of the form "inside:<child>:<parent>" or "disjoint:<a>:<b>".
check_cidrs() {
  python3 - "$@" <<'PY'
import ipaddress, sys

bad = False
for rule in sys.argv[1:]:
    kind, a, b = rule.split(":")
    na, nb = ipaddress.ip_network(a), ipaddress.ip_network(b)
    if kind == "inside" and not na.subnet_of(nb):
        print(f"config error: {a} must be inside {b}", file=sys.stderr); bad = True
    if kind == "disjoint" and na.overlaps(nb):
        print(f"config error: {a} must not overlap {b}", file=sys.stderr); bad = True
if bad:
    sys.exit(1)
PY
}

cluster_exists() { aws eks describe-cluster --name "$CLUSTER_NAME" >/dev/null 2>&1; }

nodegroup_exists() { # <name>
  aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$1" >/dev/null 2>&1
}

vpc_id() { aws eks describe-cluster --name "$CLUSTER_NAME" --query 'cluster.resourcesVpcConfig.vpcId' --output text; }

# Delete the Ingress, wait until the controller has removed the ALB, then uninstall the controller.
# The ALB's ENIs and security groups are not owned by eksctl and would block the VPC deletion.
delete_alb_and_controller() {
  kubectl delete -f "$RENDER_DIR/manifests/03-alb.yaml" --ignore-not-found --wait=true --timeout=300s || true
  kubectl delete -f "$RENDER_DIR/manifests/01-app.yaml" -f "$RENDER_DIR/manifests/02-ingress-class.yaml" --ignore-not-found || true
  kubectl delete pod client --ignore-not-found || true

  local _
  for _ in $(seq 1 60); do
    aws elbv2 describe-load-balancers --names "$ALB_NAME" >/dev/null 2>&1 || break
    echo "    ALB $ALB_NAME still deleting..."
    sleep 10
  done
  if aws elbv2 describe-load-balancers --names "$ALB_NAME" >/dev/null 2>&1; then
    echo "ALB $ALB_NAME still exists after 10 minutes. Delete it manually, then re-run." >&2
    exit 1
  fi
  helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || true
}
