#!/usr/bin/env bash
set -Eeuo pipefail

source /usr/local/bin/runtime-env.sh

[[ -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ]]
pgrep -x labwc >/dev/null
pgrep -x sunshine >/dev/null
s6-setuidgid abc env XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR}" WAYLAND_DISPLAY="${WAYLAND_DISPLAY}" \
  wlr-randr | grep -q '^HEADLESS-1'
s6-setuidgid abc env XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR}" \
  pactl info | grep -q '^Server Name:'
