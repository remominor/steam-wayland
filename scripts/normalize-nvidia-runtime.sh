#!/usr/bin/env bash
set -euo pipefail

render_node="${DRI_NODE:-/dev/dri/renderD128}"
[[ -e "${render_node}" ]] || { echo "fatal: render node ${render_node} is unavailable" >&2; exit 1; }

if ! command -v nvidia-smi >/dev/null 2>&1; then
  echo "fatal: NVIDIA runtime injection is unavailable (nvidia-smi not found)" >&2
  exit 1
fi

echo "NVIDIA runtime detected; renderer=${render_node}"
nvidia-smi --query-gpu=index,name,driver_version,uuid --format=csv,noheader || true

mkdir -p /etc/OpenCL/vendors /etc/vulkan/icd.d /etc/glvnd/egl_vendor.d
[[ -n "$(find /etc/OpenCL/vendors -name '*nvidia*.icd' -print -quit 2>/dev/null)" ]] || \
  printf '%s\n' 'libnvidia-opencl.so.1' > /etc/OpenCL/vendors/nvidia.icd

if [[ -z "$(find /usr/share/vulkan/icd.d /etc/vulkan/icd.d -name '*nvidia*.json' -print -quit 2>/dev/null)" ]]; then
  printf '%s\n' '{"file_format_version":"1.0.0","ICD":{"library_path":"libGLX_nvidia.so.0","api_version":"1.1.0"}}' \
    > /etc/vulkan/icd.d/nvidia_icd.json
fi

if [[ -z "$(find /usr/share/glvnd/egl_vendor.d /etc/glvnd/egl_vendor.d -name '*nvidia*.json' -print -quit 2>/dev/null)" ]]; then
  printf '%s\n' '{"file_format_version":"1.0.0","ICD":{"library_path":"libEGL_nvidia.so.0"}}' \
    > /etc/glvnd/egl_vendor.d/10_nvidia.json
fi

if ! ldconfig -p | grep -q 'nvidia-drm_gbm.so'; then
  for candidate in \
    /usr/lib/x86_64-linux-gnu/gbm/nvidia-drm_gbm.so \
    /usr/lib64/gbm/nvidia-drm_gbm.so \
    /usr/lib/gbm/nvidia-drm_gbm.so \
    /usr/local/lib/gbm/nvidia-drm_gbm.so \
    /usr/local/lib64/gbm/nvidia-drm_gbm.so; do
    [[ -f "${candidate}" ]] || continue
    install -D -m 755 "${candidate}" /usr/lib/x86_64-linux-gnu/gbm/nvidia-drm_gbm.so
    ldconfig
    echo "Installed NVIDIA GBM backend from ${candidate}"
    break
  done
fi

ldconfig -p | grep -E 'nvidia|EGL|encode' | head -n 30 || true
