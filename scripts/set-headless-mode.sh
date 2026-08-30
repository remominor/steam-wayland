#!/usr/bin/env bash
set -euo pipefail

source /usr/local/bin/runtime-env.sh
output="${WLR_OUTPUT:-HEADLESS-1}"
default_mode="${DEFAULT_MODE:-1920x1080@60}"
mode_policy="${OUTPUT_MODE_POLICY:-client}"

case "${1:-client}" in
  client)
    case "${mode_policy}" in
      fixed) mode="${default_mode}" ;;
      client)
        width="${SUNSHINE_CLIENT_WIDTH:-1920}"
        height="${SUNSHINE_CLIENT_HEIGHT:-1080}"
        fps="${SUNSHINE_CLIENT_FPS:-60}"
        [[ "${width}" =~ ^[0-9]+$ && "${height}" =~ ^[0-9]+$ && "${fps}" =~ ^[0-9]+([.][0-9]+)?$ ]] || {
          echo "Invalid Sunshine client mode; using ${default_mode}" >&2
          mode="${default_mode}"
        }
        mode="${mode:-${width}x${height}@${fps}}"
        ;;
      *)
        echo "Invalid OUTPUT_MODE_POLICY=${mode_policy}; expected fixed or client" >&2
        exit 2
        ;;
    esac
    ;;
  default) mode="${default_mode}" ;;
  *) mode="$1" ;;
esac

for _ in $(seq 1 20); do
  wlr-randr >/dev/null 2>&1 && break
  sleep 0.5
done

if wlr-randr --output "${output}" --custom-mode "${mode}Hz" --scale 1; then
  echo "Applied ${output} mode ${mode}Hz"
  exit 0
fi

echo "warning: failed to apply ${mode}; restoring ${default_mode}" >&2
wlr-randr --output "${output}" --custom-mode "${default_mode}Hz" --scale 1
