# Use multi-stage build with caching optimizations
# Base image MUST be CUDA 12.8 or newer for RTX 5090 (Blackwell) support.
FROM nvidia/cuda:12.8.1-devel-ubuntu22.04

# Consolidated environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    PIP_PREFER_BINARY=1 \
    PYTHONUNBUFFERED=1 \
    CMAKE_BUILD_PARALLEL_LEVEL=8

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# --- CRITICAL CHANGE: Set standard RunPod working directory ---
WORKDIR /workspace

# Install Python 3.10 specifically and make it the default
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 python3.10-dev python3.10-distutils python3-pip python3.10-venv \
    curl ffmpeg ninja-build git git-lfs wget aria2 vim libgl1 libglib2.0-0 build-essential gcc \
    && ln -sf /usr/bin/python3.10 /usr/bin/python \
    && ln -sf /usr/bin/python3.10 /usr/bin/python3 \
    && curl -sS https://bootstrap.pypa.io/get-pip.py | python3.10 \
    && ln -sf /usr/local/bin/pip /usr/bin/pip \
    && ln -sf /usr/local/bin/pip /usr/bin/pip3 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Verify Python version
RUN python --version && pip --version

# install runpod and requests for python
RUN pip install runpod requests websocket-client

# ----------------------------------------------
# --- ComfyUI Installation ---
# ----------------------------------------------
# Clone ComfyUI repository into /workspace/ComfyUI
RUN git clone https://github.com/comfyanonymous/ComfyUI.git

WORKDIR /workspace/ComfyUI

# Install core ComfyUI dependencies
# CRITICAL: Install PyTorch built for CUDA 12.8 (cu128) for RTX 5090 compatibility.
RUN pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128 \
    && pip install -r requirements.txt

# ----------------------------------------------
# --- Custom Nodes Installation ---
# ----------------------------------------------
WORKDIR /workspace/ComfyUI/custom_nodes

# 1. ComfyUI Manager
RUN git clone https://github.com/Comfy-Org/ComfyUI-Manager.git \
    && pip install -r ComfyUI-Manager/requirements.txt

# 2. ComfyUI-GGUF (Requires llama-cpp-python)
RUN git clone https://github.com/city96/ComfyUI-GGUF.git\
    && pip install -r ComfyUI-GGUF/requirements.txt

# 3. ComfyUI-VideoHelperSuite (Requires dependencies like moviepy)
RUN git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git \
    && pip install -r ComfyUI-VideoHelperSuite/requirements.txt

# ----------------------------------------------
# --- Final Cleanup and Handler Setup ---
# ----------------------------------------------
# Change back to the main workspace directory
WORKDIR /workspace

# Add RunPod Handler and Docker container start script
COPY start.sh rp_handler.py ./

# Configure ComfyUI to use the RunPod volume for models
COPY extra_model_paths.yaml /workspace/ComfyUI/extra_model_paths.yaml

COPY comfy-manager-set-mode.sh /usr/local/bin/comfy-manager-set-mode
RUN chmod +x /usr/local/bin/comfy-manager-set-mode

RUN chmod +x /start.sh
ENTRYPOINT /start.sh
