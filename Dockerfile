# --- Base image for RTX 5090 (CUDA 12.8+) ---
FROM nvidia/cuda:12.8.1-devel-ubuntu22.04

# --- Environment variables ---
ENV DEBIAN_FRONTEND=noninteractive \
    PIP_PREFER_BINARY=1 \
    PYTHONUNBUFFERED=1 \
    CMAKE_BUILD_PARALLEL_LEVEL=8

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# --- Working directory ---
WORKDIR /workspace

# --- Install system dependencies and Python 3.10 ---
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

RUN python --version && pip --version

# --- Install base Python packages ---
RUN pip install requests runpod==1.7.9 websocket-client onnxruntime-gpu triton mutagen

# ----------------------------------------------
# --- Install ComfyUI ---
# ----------------------------------------------
WORKDIR /workspace
RUN git clone https://github.com/comfyanonymous/ComfyUI.git
WORKDIR /workspace/ComfyUI

# --- Install PyTorch for CUDA 12.8 (RTX 5090 support) ---
RUN pip install torch==2.7.0 torchvision==0.22.0 torchaudio==2.7.0 xformers==0.0.30 --index-url https://download.pytorch.org/whl/cu128 \
    && pip install -r requirements.txt

# ----------------------------------------------
# --- Install Custom Nodes ---
# ----------------------------------------------
WORKDIR /workspace/ComfyUI/custom_nodes

RUN bash -c '\
install_reqs() { [ -f "$1/requirements.txt" ] && pip install -r "$1/requirements.txt" || echo "No requirements for $1"; }; \
rm -rf /workspace/ComfyUI/custom_nodes/ComfyUI-Manager && \
git clone https://github.com/Comfy-Org/ComfyUI-Manager.git && install_reqs ComfyUI-Manager; \
git clone https://github.com/city96/ComfyUI-GGUF.git && install_reqs ComfyUI-GGUF; \
git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git && install_reqs ComfyUI-VideoHelperSuite; \
git clone https://github.com/kijai/ComfyUI-KJNodes.git && install_reqs ComfyUI-KJNodes; \
git clone https://github.com/yuvraj108c/ComfyUI-Rife-Tensorrt.git && install_reqs ComfyUI-Rife-Tensorrt; \
git clone https://github.com/kijai/ComfyUI-WanVideoWrapper.git && install_reqs ComfyUI-WanVideoWrapper; \
git clone https://github.com/kijai/ComfyUI-WanAnimatePreprocess.git && install_reqs ComfyUI-WanAnimatePreprocess; \
git clone https://github.com/kijai/ComfyUI-segment-anything-2.git && install_reqs ComfyUI-segment-anything-2; \
# --- SageAttention Installation ---
git clone https://github.com/thu-ml/SageAttention.git && \
cd SageAttention && python setup.py install && cd ..; \
'

# ----------------------------------------------
# --- Final Setup ---
# ----------------------------------------------
WORKDIR /workspace
COPY start.sh rp_handler.py ./
COPY extra_model_paths.yaml /workspace/ComfyUI/extra_model_paths.yaml
COPY comfy-manager-set-mode.sh /usr/local/bin/comfy-manager-set-mode

RUN chmod +x /usr/local/bin/comfy-manager-set-mode /start.sh

ENTRYPOINT ["/start.sh"]
