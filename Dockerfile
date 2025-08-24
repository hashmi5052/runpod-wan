# Use multi-stage build with caching optimizations
FROM nvidia/cuda:12.8.1-devel-ubuntu22.04

# Consolidated environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    PIP_PREFER_BINARY=1 \
    PYTHONUNBUFFERED=1 \
    HF_HOME=/models/huggingface \
    CMAKE_BUILD_PARALLEL_LEVEL=8

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

WORKDIR /workspace

# Install system deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 python3.10-dev python3.10-distutils python3-venv \
    curl git git-lfs wget aria2 ffmpeg build-essential ninja-build libgl1 libglib2.0-0 \
    && ln -sf /usr/bin/python3.10 /usr/bin/python \
    && curl -sS https://bootstrap.pypa.io/get-pip.py | python3.10 \
    && ln -sf /usr/local/bin/pip /usr/bin/pip \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Python deps
RUN pip install --upgrade pip \
    && pip install runpod requests websocket-client

# Clone ComfyUI
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI

# Install ComfyUI dependencies
RUN pip install -r /workspace/ComfyUI/requirements.txt

# --- Start of new additions to your Dockerfile ---

# Set ComfyUI directory as the working directory and create subdirectories
WORKDIR /workspace/ComfyUI

RUN mkdir -p /workspace/ComfyUI/models/checkpoints \
    /workspace/ComfyUI/models/vae \
    /workspace/ComfyUI/models/clip \
    /workspace/ComfyUI/models/clip_vision \
    /workspace/ComfyUI/custom_nodes

# Clone and install custom nodes
RUN git clone https://github.com/ltdrdata/ComfyUI-Manager custom_nodes/ComfyUI-Manager \
    && git clone https://github.com/rgthree/rgthree-comfy custom_nodes/rgthree-comfy

# Install any required python dependencies for the custom nodes
RUN pip install -r custom_nodes/ComfyUI-Manager/requirements.txt \
    && pip install -r custom_nodes/rgthree-comfy/requirements.txt

# Download all necessary models and assets
RUN aria2c -q -c -x 16 -s 16 -k 1M -d /workspace/ComfyUI/models/checkpoints -o flux1-kontext-dev.safetensors https://huggingface.co/black-forest-labs/FLUX.1-Kontext-dev/resolve/main/flux1-kontext-dev.safetensors \
    && aria2c -q -c -x 16 -s 16 -k 1M -d /workspace/ComfyUI/models/vae -o vae.safetensors https://huggingface.co/stabilityai/sd-vae-ft-mse-original/resolve/main/vae-ft-mse-840000-ema-pruned.safetensors \
    && aria2c -q -c -x 16 -s 16 -k 1M -d /workspace/ComfyUI/models/clip_vision -o clip_vision.safetensors https://huggingface.co/openai/clip-vit-large-patch14/resolve/main/pytorch_model.safetensors \
    && aria2c -q -c -x 16 -s 16 -k 1M -d /workspace/ComfyUI/models/clip -o text_encoder.safetensors https://huggingface.co/openai/clip-vit-large-patch14/resolve/main/pytorch_model.safetensors

# Return to root directory
WORKDIR /workspace

# --- End of new additions to your Dockerfile ---

# Copy handler + start script
COPY rp_handler.py /rp_handler.py
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 3000

ENTRYPOINT ["/start.sh"]
