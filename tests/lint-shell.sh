#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
status=0
while IFS= read -r script; do
  if ! bash -n "${script}"; then status=1; fi
done < <(find "${repo_root}/scripts" "${repo_root}/tests" "${repo_root}/root/etc/s6-overlay" -type f \
  \( -name '*.sh' -o -name run \) -print)
exit "${status}"
