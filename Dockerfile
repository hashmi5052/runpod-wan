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
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI \
 && pip install --no-cache-dir -r /workspace/ComfyUI/requirements.txt

# -----------------
# Prepare model folders
# -----------------
RUN mkdir -p /workspace/ComfyUI/models/diffusion_models \
    /workspace/ComfyUI/models/vae \
    /workspace/ComfyUI/models/text_encoders \
    /workspace/ComfyUI/models/upscale_models \
    /workspace/ComfyUI/custom_nodes

# -----------------
# Download Diffusion / VAE / CLIP Models with aria2c (progress shown)
# -----------------
RUN aria2c -x 4 -s 4 -o /workspace/ComfyUI/models/diffusion_models/flux1-kontext-dev-Q4_0.gguf \
    https://huggingface.co/QuantStack/FLUX.1-Kontext-dev-GGUF/resolve/main/flux1-kontext-dev-Q4_0.gguf

RUN aria2c -x 4 -s 4 -o /workspace/ComfyUI/models/vae/ae.safetensors \
    https://huggingface.co/lovis93/testllm/resolve/main/ae.safetensors

RUN aria2c -x 4 -s 4 -o /workspace/ComfyUI/models/text_encoders/clip_l.safetensors \
    https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors \
 && aria2c -x 4 -s 4 -o /workspace/ComfyUI/models/text_encoders/t5xxl_fp8_e4m3fn.safetensors \
    https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors

# -----------------
# Download Upscalers with aria2c (progress shown)
# -----------------
RUN aria2c -x 4 -s 4 -o /workspace/ComfyUI/models/upscale_models/RealESRGAN_x2.pth \
    https://huggingface.co/ai-forever/Real-ESRGAN/resolve/a86fc6182b4650b4459cb1ddcb0a0d1ec86bf3b0/RealESRGAN_x2.pth \
 && aria2c -x 4 -s 4 -o /workspace/ComfyUI/models/upscale_models/RealESRGAN_x4.pth \
    https://huggingface.co/ai-forever/Real-ESRGAN/resolve/a86fc6182b4650b4459cb1ddcb0a0d1ec86bf3b0/RealESRGAN_x4.pth \
 && aria2c -x 4 -s 4 -o /workspace/ComfyUI/models/upscale_models/RealESRGAN_x8.pth \
    https://huggingface.co/ai-forever/Real-ESRGAN/resolve/a86fc6182b4650b4459cb1ddcb0a0d1ec86bf3b0/RealESRGAN_x8.pth \
 && aria2c -x 4 -s 4 -o /workspace/ComfyUI/models/upscale_models/4x_foolhardy_Remacri.pth \
    https://huggingface.co/FacehugmanIII/4x_foolhardy_Remacri/resolve/main/4x_foolhardy_Remacri.pth \
 && aria2c -x 4 -s 4 -o /workspace/ComfyUI/models/upscale_models/4x-UltraSharp.pth \
    https://huggingface.co/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth \
 && aria2c -x 4 -s 4 -o /workspace/ComfyUI/models/upscale_models/4x_NMKD-Siax_200k.pth \
    https://huggingface.co/gemasai/4x_NMKD-Siax_200k/resolve/main/4x_NMKD-Siax_200k.pth \
 && aria2c -x 4 -s 4 -o /workspace/ComfyUI/models/upscale_models/8x_NMKD-Superscale_150000_G.pth \
    https://huggingface.co/uwg/upscaler/resolve/main/ESRGAN/8x_NMKD-Superscale_150000_G.pth \
 && aria2c -x 4 -s 4 -o /workspace/ComfyUI/models/upscale_models/8x_NMKD-Faces_160000_G.pth \
    https://huggingface.co/gemasai/8x_NMKD-Faces_160000_G/resolve/main/8x_NMKD-Faces_160000_G.pth

# -----------------
# Clone Custom Nodes
# -----------------
RUN git clone https://github.com/Comfy-Org/ComfyUI-Manager.git /workspace/ComfyUI/custom_nodes/ComfyUI-Manager \
 && git clone https://github.com/city96/ComfyUI-GGUF.git /workspace/ComfyUI/custom_nodes/ComfyUI-GGUF

# Install requirements for custom nodes if present
RUN if [ -f /workspace/ComfyUI/custom_nodes/ComfyUI-Manager/requirements.txt ]; then \
        pip install --no-cache-dir -r /workspace/ComfyUI/custom_nodes/ComfyUI-Manager/requirements.txt; \
    fi
RUN if [ -f /workspace/ComfyUI/custom_nodes/ComfyUI-GGUF/requirements.txt ]; then \
        pip install --no-cache-dir -r /workspace/ComfyUI/custom_nodes/ComfyUI-GGUF/requirements.txt; \
    fi

# -----------------
# Copy scripts
# -----------------
COPY rp_handler.py /rp_handler.py
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 3000
ENTRYPOINT ["/start.sh"]
