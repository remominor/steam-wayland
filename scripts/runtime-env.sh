#!/usr/bin/env bash

runtime_uid="$(id -u abc)"
export HOME=/config
export LANG="${LANG:-C.UTF-8}"
export LC_ALL="${LC_ALL:-C.UTF-8}"
export XDG_CONFIG_HOME=/config/.config
export XDG_DATA_HOME=/config/.local/share
export XDG_CACHE_HOME=/config/.cache
export XDG_RUNTIME_DIR="/run/user/${runtime_uid}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export DISPLAY="${DISPLAY:-:0}"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
export PIPEWIRE_RUNTIME_DIR="${XDG_RUNTIME_DIR}"
export PULSE_RUNTIME_PATH="${XDG_RUNTIME_DIR}/pulse"
export LIBSEAT_BACKEND="${LIBSEAT_BACKEND:-seatd}"
export SEATD_SOCK="${SEATD_SOCK:-/run/seatd.sock}"
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=XFCE
export XDG_SESSION_DESKTOP=xfce
export XDG_SEAT="${XDG_SEAT:-seat0}"
export WLR_BACKENDS="${WLR_BACKENDS:-headless,libinput}"
export WLR_LIBINPUT_NO_DEVICES="${WLR_LIBINPUT_NO_DEVICES:-1}"
export WLR_RENDER_DRM_DEVICE="${DRI_NODE:-/dev/dri/renderD128}"
export DEFAULT_MODE="${DEFAULT_MODE:-1920x1080@60}"
export OUTPUT_MODE_POLICY="${OUTPUT_MODE_POLICY:-client}"

# Auto-select a compatible renderer unless the user explicitly overrides it.
if [[ -z "${WLR_RENDERER:-}" || "${WLR_RENDERER}" == "auto" ]]; then
  if [[ -e /dev/nvidiactl || -r /proc/driver/nvidia/version ]]; then
    export WLR_RENDERER=gles2
  else
    unset WLR_RENDERER
  fi
fi
