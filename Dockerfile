# =============================================================================
# ComfyUI — Thin RunPod image (apps + packages live on network volume)
# Base: PyTorch 2.8.0, CUDA 12.8.1, Ubuntu 24.04
#
# RunPod pre-caches their pytorch images, so only our tiny layer gets pulled.
# First boot: clones ComfyUI + installs deps to /workspace (~3 min)
# Subsequent boots: everything cached on network volume (~30 sec)
# =============================================================================
FROM runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ── System deps (small layer — git, opencv libs, ffmpeg) ─────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        git git-lfs libgl1 libglib2.0-0 \
        libsm6 libxext6 libxrender-dev ffmpeg \
        openssh-server \
    && git lfs install \
    && mkdir -p /var/run/sshd \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ── Startup script ──────────────────────────────────────────────────────────
COPY start.sh /opt/start.sh
RUN chmod +x /opt/start.sh

WORKDIR /
CMD ["/opt/start.sh"]
