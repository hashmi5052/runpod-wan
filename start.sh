#!/usr/bin/env bash
set -e

echo "worker-comfyui - Starting ComfyUI"

# Use tcmalloc if available
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1 || true)"
if [ -n "$TCMALLOC" ]; then
    export LD_PRELOAD="${TCMALLOC}"
fi

export PYTHONUNBUFFERED=true

# Optional: set ComfyUI Manager offline mode
if command -v comfy-manager-set-mode &> /dev/null; then
    comfy-manager-set-mode offline || echo "worker-comfyui - Could not set ComfyUI-Manager network_mode" >&2
fi

cd /workspace/ComfyUI

# Start ComfyUI
python -u main.py \
    --port 3000 \
    --listen \
    --disable-auto-launch \
    --disable-metadata \
    --log-stdout &

# Wait for ComfyUI API
echo "worker-comfyui - Waiting for ComfyUI to be reachable"
until curl -s http://127.0.0.1:3000/ > /dev/null; do
    echo "worker-comfyui - Waiting for ComfyUI server..."
    sleep 1
done

echo "worker-comfyui - ComfyUI is up. Starting RunPod Handler."
python -u /rp_handler.py
