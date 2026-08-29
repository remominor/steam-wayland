#!/usr/bin/env bash
set -euo pipefail

container="${1:-steam-wayland}"
docker exec --user abc "${container}" bash -lc '
  set -euo pipefail
  source /usr/local/bin/runtime-env.sh
  wlr-randr | grep -A4 "^HEADLESS-1"
  test -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}"
  pgrep -x Xwayland >/dev/null
'
