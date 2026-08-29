#!/usr/bin/env bash
set -euo pipefail

shopt -s nullglob
devices=(/dev/uinput /dev/uhid /dev/fuse /dev/dri/card* /dev/dri/renderD* /dev/input/event*)

for device in "${devices[@]}"; do
  [[ -c "${device}" ]] || continue
  gid="$(stat -c '%g' "${device}")"
  mode="$(stat -c '%A' "${device}")"
  group_name="$(getent group "${gid}" | cut -d: -f1 || true)"
  if [[ -z "${group_name}" ]]; then
    group_name="hostdev-${gid}"
    groupadd --gid "${gid}" "${group_name}"
  fi
  usermod -a -G "${group_name}" abc
  if [[ "${mode:4:2}" != "rw" ]]; then
    echo "warning: ${device} is not group read/write (${mode}); fix its host permissions" >&2
  fi
done
