FROM nvidia/cuda:12.8.1-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_PREFER_BINARY=1 \
    PYTHONUNBUFFERED=1 \
    CMAKE_BUILD_PARALLEL_LEVEL=8

WORKDIR /workspace

# -----------------
# Install system dependencies
# -----------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 python3.10-dev python3.10-distutils python3-venv \
    curl git git-lfs wget aria2 ffmpeg build-essential ninja-build libgl1 libglib2.0-0 ca-certificates \
    && ln -sf /usr/bin/python3.10 /usr/bin/python \
    && curl -sS https://bootstrap.pypa.io/get-pip.py | python3.10 \
    && ln -sf /usr/local/bin/pip /usr/bin/pip \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# -----------------
# Python base packages
# -----------------
RUN pip install --upgrade pip \
    && pip install runpod requests websocket-client

# -----------------
# Clone ComfyUI
# -----------------
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI
RUN pip install -r /workspace/ComfyUI/requirements.txt

# -----------------
# Prepare model folders
# -----------------
RUN mkdir -p /workspace/ComfyUI/models/diffusion_models \
    /workspace/ComfyUI/models/vae \
    /workspace/ComfyUI/models/clip \
    /workspace/ComfyUI/custom_nodes

# -----------------
# Download Models
# -----------------
# Flux-Kontext GGUF model → diffusion_models
RUN wget -O /workspace/ComfyUI/models/diffusion_models/flux1-kontext-dev-Q4_0.gguf \
    https://huggingface.co/QuantStack/FLUX.1-Kontext-dev-GGUF/resolve/main/flux1-kontext-dev-Q4_0.gguf

# VAE → vae
RUN wget -O /workspace/ComfyUI/models/vae/ae.safetensors \
    https://huggingface.co/lovis93/testllm/resolve/main/ae.safetensors

# CLIP models → clip
RUN wget -O /workspace/ComfyUI/models/clip/clip_l.safetensors \
    https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors && \
    wget -O /workspace/ComfyUI/models/clip/t5xxl_fp8_e4m3fn.safetensors \
    https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors

# -----------------
# Clone Custom Nodes
# -----------------
RUN git clone https://github.com/Comfy-Org/ComfyUI-Manager.git /workspace/ComfyUI/custom_nodes/ComfyUI-Manager \
 && git clone https://github.com/city96/ComfyUI-GGUF.git /workspace/ComfyUI/custom_nodes/ComfyUI-GGUF

# Install requirements for custom nodes if present
RUN if [ -f /workspace/ComfyUI/custom_nodes/ComfyUI-Manager/requirements.txt ]; then \
        pip install -r /workspace/ComfyUI/custom_nodes/ComfyUI-Manager/requirements.txt; \
    fi
RUN if [ -f /workspace/ComfyUI/custom_nodes/ComfyUI-GGUF/requirements.txt ]; then \
        pip install -r /workspace/ComfyUI/custom_nodes/ComfyUI-GGUF/requirements.txt; \
    fi

# -----------------
# Copy scripts
# -----------------
COPY rp_handler.py /rp_handler.py
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 3000
ENTRYPOINT ["/start.sh"]
