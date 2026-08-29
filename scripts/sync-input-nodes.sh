#!/usr/bin/env bash
set -euo pipefail

mkdir -p /dev/input
fallback_gid="$(stat -c '%g' /dev/uinput 2>/dev/null || printf '0')"

while true; do
  for sys_event in /sys/class/input/event*; do
    [[ -e "${sys_event}/dev" ]] || continue
    event_name="${sys_event##*/}"
    device="/dev/input/${event_name}"
    [[ -e "${device}" ]] && continue
    IFS=: read -r major minor < "${sys_event}/dev"
    if mknod "${device}" c "${major}" "${minor}" 2>/dev/null; then
      chgrp "${fallback_gid}" "${device}" || true
      chmod g+rw "${device}" || true
      echo "Materialized ${device} (${major}:${minor})"
    fi
  done
  sleep 2
done
