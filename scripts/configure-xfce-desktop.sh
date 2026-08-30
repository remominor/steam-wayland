#!/usr/bin/env bash
set -euo pipefail

source /usr/local/bin/runtime-env.sh

# xfconf needs the XFCE session bus, which may appear shortly after Labwc
# starts. Retry so this also works with an existing config volume's old,
# one-shot autostart migration.
for _ in $(seq 1 30); do
  if {
    # This is a headless streamed desktop. Do not expose host filesystem,
    # removable-device, or network-volume icons through xfdesktop/GVFS.
    for property in \
      /desktop-icons/file-icons/show-filesystem \
      /desktop-icons/file-icons/show-home \
      /desktop-icons/file-icons/show-network \
      /desktop-icons/file-icons/show-removable \
      /desktop-icons/file-icons/show-trash; do
      xfconf-query -c xfce4-desktop -p "${property}" -n -t bool -s false
    done

    # Keep the streamed desktop visually clean; applications remain available
    # from the XFCE panel/menu and Labwc fallback menu.
    xfconf-query -c xfce4-desktop -p /desktop-icons/show-thumbnails -n -t bool -s false
  }; then
    exit 0
  fi
  sleep 0.5
done

exit 1
