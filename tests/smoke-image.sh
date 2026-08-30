#!/usr/bin/env bash
set -euo pipefail

image="${1:-steam-wayland:local}"
docker run --rm --entrypoint /bin/bash "${image}" -lc '
  set -euo pipefail
  for command in labwc wlr-randr Xwayland sunshine pipewire wireplumber umu-run steam dwarfs firefox-esr foot thunar mousepad pavucontrol xfce4-terminal; do
    command -v "${command}" >/dev/null || { echo "missing ${command}" >&2; exit 1; }
  done
  test -f /defaults/labwc/rc.xml
  test -f /defaults/labwc/menu.xml
  test -f /defaults/sunshine/sunshine.conf
  test -f /etc/s6-overlay/s6-rc.d/svc-sunshine/run
  grep -q "capture = wlr" /defaults/sunshine/sunshine.conf
  grep -q "encoder = nvenc" /defaults/sunshine/sunshine.conf
  test "$(getent passwd abc | cut -d: -f7)" = /bin/bash
  test "$(readlink -f /usr/bin/steamdeps)" = "$(readlink -f /bin/true)"
'
