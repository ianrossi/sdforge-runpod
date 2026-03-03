# =============================================================================
# SD Forge + ComfyUI — RunPod B200/Blackwell-ready image
# Base: PyTorch 2.8.0, CUDA 12.8.1, Ubuntu 24.04
# =============================================================================
FROM runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ── System deps ──────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        git git-lfs libgl1 libglib2.0-0 \
        libsm6 libxext6 libxrender-dev wget aria2 ffmpeg \
        google-perftools \
    && git lfs install \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ── SD Forge WebUI ───────────────────────────────────────────────────────────
RUN git clone --depth 1 https://github.com/lllyasviel/stable-diffusion-webui-forge.git /opt/forge

WORKDIR /opt/forge
RUN pip install --no-cache-dir -r requirements_versions.txt \
    && pip install --no-cache-dir xformers

# Remove default model dirs (will be symlinked to NV at runtime)
RUN rm -rf models/Stable-diffusion models/Lora models/VAE \
           models/ControlNet models/ESRGAN embeddings outputs

# ── ComfyUI ──────────────────────────────────────────────────────────────────
RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git /opt/comfyui

WORKDIR /opt/comfyui
RUN pip install --no-cache-dir -r requirements.txt

# ComfyUI Manager (easy custom-node management from the UI)
RUN git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git \
        /opt/comfyui/custom_nodes/ComfyUI-Manager \
    && (pip install --no-cache-dir \
        -r /opt/comfyui/custom_nodes/ComfyUI-Manager/requirements.txt || true)

# Remove default model dirs (will be symlinked to NV at runtime)
RUN rm -rf models/checkpoints models/loras models/vae models/clip \
           models/controlnet models/upscale_models models/embeddings \
           models/diffusion_models models/text_encoders output

# ── Startup script ───────────────────────────────────────────────────────────
COPY start.sh /opt/start.sh
RUN chmod +x /opt/start.sh

WORKDIR /
CMD ["/opt/start.sh"]
