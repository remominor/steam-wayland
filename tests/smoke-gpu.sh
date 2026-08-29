#!/usr/bin/env bash
set -euo pipefail

container="${1:-steam-wayland}"
docker exec "${container}" bash -lc '
  set -euo pipefail
  nvidia-smi
  test -e "${DRI_NODE:-/dev/dri/renderD128}"
  unset DISPLAY WAYLAND_DISPLAY
  vulkaninfo --summary
  ldconfig -p | grep -E "nvidia|encode"
'
