#!/usr/bin/env bash
set -euo pipefail

image="${1:-steam-wayland:local}"
docker run --rm --entrypoint /bin/bash "${image}" -lc '
  set -euo pipefail
  for command in labwc wlr-randr Xwayland sunshine pipewire wireplumber umu-run steam wine winetricks gamescope dwarfs gst-launch-1.0 firefox-esr foot thunar thunar-volman mousepad pavucontrol xfce4-terminal xfce4-session xfce4-panel xfdesktop xfsettingsd xfce4-display-settings; do
    command -v "${command}" >/dev/null || { echo "missing ${command}" >&2; exit 1; }
  done
  test -f /defaults/labwc/rc.xml
  test -f /defaults/labwc/menu.xml
  test -x /usr/local/bin/configure-xfce-desktop.sh
  test -x /opt/protonup-qt/ProtonUp-Qt.AppImage
  test -f /usr/share/applications/protonup-qt.desktop
  test -f /usr/share/backgrounds/steam-wayland.svg
  test -f /defaults/sunshine/sunshine.conf
  test -f /etc/s6-overlay/s6-rc.d/svc-sunshine/run
  grep -q "capture = wlr" /defaults/sunshine/sunshine.conf
  grep -q "encoder = nvenc" /defaults/sunshine/sunshine.conf
  test "$(getent passwd abc | cut -d: -f7)" = /bin/bash
  test "$(readlink -f /usr/bin/steamdeps)" = "$(readlink -f /bin/true)"
'
