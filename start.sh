#!/usr/bin/env bash

echo "worker-comfyui - Starting ComfyUI"

# Memory optimization (optional, safe to keep)
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1 || true)"
if [[ -n "$TCMALLOC" ]]; then
    export LD_PRELOAD="${TCMALLOC}"
fi

export PYTHONUNBUFFERED=true

cd /workspace/ComfyUI

# Start ComfyUI
python -u main.py \
    --port 3000 \
    --listen \
    --disable-auto-launch \
    --disable-metadata \
    --verbose \
    --log-stdout &

# Wait until ComfyUI is reachable
echo "worker-comfyui - Waiting for ComfyUI to be reachable"
until curl -s http://127.0.0.1:3000/ > /dev/null; do
    echo "worker-comfyui - Waiting for ComfyUI server..."
    sleep 1
done

echo "worker-comfyui - ComfyUI is up. Starting RunPod Handler."
python -u /rp_handler.py
