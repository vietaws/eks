#!/usr/bin/env bash
# Render the *.yaml templates into .rendered/ from ../config.env (up.sh, stage.sh and down.sh do this
# automatically). Use it when you follow the README step by step. Makes no AWS calls.
# Usage: ./scripts/render.sh
set -euo pipefail

# shellcheck source=SCRIPTDIR/../../lib/common.sh
. "$(dirname "$0")/../../lib/common.sh"
load_config
render
