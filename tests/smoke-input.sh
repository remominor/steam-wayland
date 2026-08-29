#!/usr/bin/env bash
set -euo pipefail

container="${1:-steam-wayland}"
docker exec "${container}" bash -lc '
  set -euo pipefail
  test -c /dev/uinput
  test -r /dev/uinput
  test -w /dev/uinput
  for sys_event in /sys/class/input/event*; do
    [[ -e "${sys_event}/dev" ]] || continue
    test -c "/dev/input/${sys_event##*/}"
  done
'
