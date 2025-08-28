#!/usr/bin/env bash
set -euo pipefail

echo "[worker-comfyui] Starting ComfyUI..."

# Memory optimization (optional)
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1 || true)"
if [[ -n "$TCMALLOC" ]]; then
    export LD_PRELOAD="${TCMALLOC}"
    echo "[worker-comfyui] Using TCMalloc: $TCMALLOC"
fi

export PYTHONUNBUFFERED=true

cd /workspace/ComfyUI

# Start ComfyUI in background
python -u main.py \
    --port 3000 \
    --listen \
    --disable-auto-launch \
    --disable-metadata \
    --verbose \
    --log-stdout &
COMFY_PID=$!

# Wait until ComfyUI is reachable or timeout after 60s
echo "[worker-comfyui] Waiting for ComfyUI to be reachable..."
for i in {1..60}; do
    if curl -s http://127.0.0.1:3000/ > /dev/null; then
        echo "[worker-comfyui] ComfyUI is up!"
        break
    fi
    echo "[worker-comfyui] Still waiting... ($i)"
    sleep 1
done

if ! kill -0 $COMFY_PID 2>/dev/null; then
    echo "[worker-comfyui] ERROR: ComfyUI process died before becoming ready."
    exit 1
fi

# Start RunPod handler
echo "[worker-comfyui] Starting RunPod handler..."
python -u /rp_handler.py &

# Wait for all background jobs
wait -n
