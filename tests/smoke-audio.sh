#!/usr/bin/env bash
set -euo pipefail

container="${1:-steam-wayland}"
docker exec --user abc "${container}" bash -lc '
  set -euo pipefail
  source /usr/local/bin/runtime-env.sh
  pactl info
  pactl list short sinks | awk "{print \$2}" | grep -qx steam-stream
'
