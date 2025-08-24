#!/usr/bin/env bash

echo "worker-comfyui - Starting ComfyUI"

TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"
export PYTHONUNBUFFERED=true
export HF_HOME="/workspace"

comfy-manager-set-mode offline || echo "worker-comfyui - Could not set ComfyUI-Manager network_mode" >&2

cd /workspace/ComfyUI

python -u main.py \
    --port 3000 \
    --listen \
    --disable-auto-launch \
    --disable-metadata \
    --verbose \
    --log-stdout &

echo "worker-comfyui - Waiting for ComfyUI to be reachable"
while ! curl -s http://127.0.0.1:3000/ > /dev/null; do
    echo "worker-comfyui - Waiting for ComfyUI server..."
    sleep 1
done

echo "worker-comfyui - ComfyUI is up. Starting RunPod Handler."
python -u /rp_handler.py
