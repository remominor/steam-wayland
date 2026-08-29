#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 1 ]] || { echo "usage: launch-umu-game.sh /config/games/game.toml" >&2; exit 2; }
source /usr/local/bin/runtime-env.sh
exec umu-run --config "$1"
