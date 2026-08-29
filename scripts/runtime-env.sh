#!/usr/bin/env bash

runtime_uid="$(id -u abc)"
export HOME=/config
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
export XDG_CURRENT_DESKTOP=labwc
export XDG_SESSION_DESKTOP=labwc
export WLR_BACKENDS="${WLR_BACKENDS:-headless,libinput}"
export WLR_RENDERER="${WLR_RENDERER:-vulkan}"
export WLR_LIBINPUT_NO_DEVICES="${WLR_LIBINPUT_NO_DEVICES:-1}"
export WLR_RENDER_DRM_DEVICE="${DRI_NODE:-/dev/dri/renderD128}"
