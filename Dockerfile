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
RUN pip install --no-cache-dir --upgrade pip \
 && pip install --no-cache-dir runpod requests websocket-client

# -----------------
# Clone ComfyUI
# -----------------
RUN git clone https://github.com/comfyanonymous/ComfyUI.git ComfyUI \
 && pip install --no-cache-dir -r ComfyUI/requirements.txt

# -----------------
# Clone Custom Nodes
# -----------------
RUN git clone https://github.com/Comfy-Org/ComfyUI-Manager.git ComfyUI/custom_nodes/ComfyUI-Manager \
 && git clone https://github.com/city96/ComfyUI-GGUF.git ComfyUI/custom_nodes/ComfyUI-GGUF

# Install requirements for custom nodes if present
RUN if [ -f ComfyUI/custom_nodes/ComfyUI-Manager/requirements.txt ]; then \
        pip install --no-cache-dir -r ComfyUI/custom_nodes/ComfyUI-Manager/requirements.txt; \
    fi
RUN if [ -f ComfyUI/custom_nodes/ComfyUI-GGUF/requirements.txt ]; then \
        pip install --no-cache-dir -r ComfyUI/custom_nodes/ComfyUI-GGUF/requirements.txt; \
    fi

# -----------------
# Copy scripts
# -----------------
COPY rp_handler.py /rp_handler.py
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 3000
ENTRYPOINT ["/start.sh"]
