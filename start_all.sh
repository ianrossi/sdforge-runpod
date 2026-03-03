#!/bin/bash
# =============================================================================
# RunPod Startup Script: SD Forge + ComfyUI (Dual UI)
# =============================================================================
# Persists everything to /workspace (network volume).
# First boot: full install (~15-25 min). Subsequent boots: fast start (~60s).
# =============================================================================
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

NV="/workspace"
FORGE_DIR="$NV/stable-diffusion-webui-forge"
COMFY_DIR="$NV/ComfyUI"
MODELS_DIR="$NV/models"
OUTPUTS_DIR="$NV/outputs"
LOGS_DIR="$NV/logs"
VENVS_DIR="$NV/venvs"

FORGE_PORT="${FORGE_PORT:-7860}"
COMFYUI_PORT="${COMFYUI_PORT:-8188}"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# ---------------------------------------------------------------------------
# 0. Directory scaffold
# ---------------------------------------------------------------------------
log "Setting up directory structure on network volume..."
mkdir -p "$MODELS_DIR"/{checkpoints,loras,vae,clip,controlnet,upscalers,embeddings}
mkdir -p "$MODELS_DIR"/{diffusion_models,text_encoders,wan}
mkdir -p "$OUTPUTS_DIR"/{forge,comfyui}
mkdir -p "$LOGS_DIR"
mkdir -p "$VENVS_DIR"

# ---------------------------------------------------------------------------
# 1. System deps (only if missing)
# ---------------------------------------------------------------------------
install_system_deps() {
    if ! command -v git-lfs &>/dev/null; then
        log "Installing system dependencies..."
        apt-get update -qq
        apt-get install -y -qq git git-lfs libgl1-mesa-glx libglib2.0-0 \
            libsm6 libxext6 libxrender-dev wget aria2 ffmpeg > /dev/null 2>&1
        git lfs install
    fi
}
install_system_deps

# ---------------------------------------------------------------------------
# 2. Install / update Stable Diffusion Forge
# ---------------------------------------------------------------------------
install_forge() {
    if [ ! -d "$FORGE_DIR" ]; then
        log "Cloning SD Forge WebUI..."
        cd "$NV"
        git clone https://github.com/lllyasviel/stable-diffusion-webui-forge.git
    else
        log "Forge directory exists, pulling latest..."
        cd "$FORGE_DIR" && git pull --ff-only 2>/dev/null || true
    fi

    # Virtual environment
    if [ ! -d "$VENVS_DIR/forge" ]; then
        log "Creating Forge venv (this takes a few minutes)..."
        python3 -m venv "$VENVS_DIR/forge"
        source "$VENVS_DIR/forge/bin/activate"
        pip install --upgrade pip wheel setuptools > /dev/null 2>&1

        # Install PyTorch (match the CUDA version on the pod)
        pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128 > /dev/null 2>&1

        # Install Forge deps
        cd "$FORGE_DIR"
        pip install -r requirements_versions.txt > /dev/null 2>&1
        pip install xformers > /dev/null 2>&1

        deactivate
        log "Forge venv ready."
    fi

    # Symlink shared model dirs into Forge's expected layout
    log "Linking shared model directories into Forge..."
    cd "$FORGE_DIR"
    mkdir -p models

    # Forge model directory names (title case / specific names)
    declare -A FORGE_LINKS=(
        ["Stable-diffusion"]="$MODELS_DIR/checkpoints"
        ["Lora"]="$MODELS_DIR/loras"
        ["VAE"]="$MODELS_DIR/vae"
        ["ControlNet"]="$MODELS_DIR/controlnet"
        ["ESRGAN"]="$MODELS_DIR/upscalers"
        ["embeddings_link"]="$MODELS_DIR/embeddings"
    )

    for forge_name in "${!FORGE_LINKS[@]}"; do
        target="${FORGE_LINKS[$forge_name]}"
        if [ "$forge_name" = "embeddings_link" ]; then
            # embeddings lives at repo root, not under models/
            rm -rf "$FORGE_DIR/embeddings" 2>/dev/null || true
            ln -sfn "$target" "$FORGE_DIR/embeddings"
        else
            rm -rf "$FORGE_DIR/models/$forge_name" 2>/dev/null || true
            ln -sfn "$target" "$FORGE_DIR/models/$forge_name"
        fi
    done

    # Point outputs to NV
    rm -rf "$FORGE_DIR/outputs" 2>/dev/null || true
    ln -sfn "$OUTPUTS_DIR/forge" "$FORGE_DIR/outputs"
}

# ---------------------------------------------------------------------------
# 3. Install / update ComfyUI
# ---------------------------------------------------------------------------
install_comfyui() {
    if [ ! -d "$COMFY_DIR" ]; then
        log "Cloning ComfyUI..."
        cd "$NV"
        git clone https://github.com/comfyanonymous/ComfyUI.git
    else
        log "ComfyUI directory exists, pulling latest..."
        cd "$COMFY_DIR" && git pull --ff-only 2>/dev/null || true
    fi

    # Virtual environment
    if [ ! -d "$VENVS_DIR/comfyui" ]; then
        log "Creating ComfyUI venv (this takes a few minutes)..."
        python3 -m venv "$VENVS_DIR/comfyui"
        source "$VENVS_DIR/comfyui/bin/activate"
        pip install --upgrade pip wheel setuptools > /dev/null 2>&1

        pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128 > /dev/null 2>&1

        cd "$COMFY_DIR"
        pip install -r requirements.txt > /dev/null 2>&1

        deactivate
        log "ComfyUI venv ready."
    fi

    # Install ComfyUI Manager (for easy custom node management)
    if [ ! -d "$COMFY_DIR/custom_nodes/ComfyUI-Manager" ]; then
        log "Installing ComfyUI Manager..."
        cd "$COMFY_DIR/custom_nodes"
        git clone https://github.com/ltdrdata/ComfyUI-Manager.git
        source "$VENVS_DIR/comfyui/bin/activate"
        cd ComfyUI-Manager
        pip install -r requirements.txt > /dev/null 2>&1 || true
        deactivate
    fi

    # Symlink shared model dirs into ComfyUI's expected layout
    log "Linking shared model directories into ComfyUI..."
    cd "$COMFY_DIR"
    mkdir -p models

    declare -A COMFY_LINKS=(
        ["checkpoints"]="$MODELS_DIR/checkpoints"
        ["loras"]="$MODELS_DIR/loras"
        ["vae"]="$MODELS_DIR/vae"
        ["clip"]="$MODELS_DIR/clip"
        ["controlnet"]="$MODELS_DIR/controlnet"
        ["upscale_models"]="$MODELS_DIR/upscalers"
        ["embeddings"]="$MODELS_DIR/embeddings"
        ["diffusion_models"]="$MODELS_DIR/diffusion_models"
        ["text_encoders"]="$MODELS_DIR/text_encoders"
    )

    for comfy_name in "${!COMFY_LINKS[@]}"; do
        target="${COMFY_LINKS[$comfy_name]}"
        rm -rf "$COMFY_DIR/models/$comfy_name" 2>/dev/null || true
        ln -sfn "$target" "$COMFY_DIR/models/$comfy_name"
    done

    # Point outputs to NV
    rm -rf "$COMFY_DIR/output" 2>/dev/null || true
    ln -sfn "$OUTPUTS_DIR/comfyui" "$COMFY_DIR/output"
}

# ---------------------------------------------------------------------------
# 4. Run installs
# ---------------------------------------------------------------------------
install_forge
install_comfyui

# ---------------------------------------------------------------------------
# 5. Start services
# ---------------------------------------------------------------------------
log "Starting ComfyUI on port $COMFYUI_PORT..."
cd "$COMFY_DIR"
source "$VENVS_DIR/comfyui/bin/activate"
python main.py \
    --listen 0.0.0.0 \
    --port "$COMFYUI_PORT" \
    --preview-method auto \
    > "$LOGS_DIR/comfyui.log" 2>&1 &
COMFY_PID=$!
deactivate
log "ComfyUI started (PID $COMFY_PID)"

log "Starting SD Forge on port $FORGE_PORT..."
cd "$FORGE_DIR"
source "$VENVS_DIR/forge/bin/activate"
python launch.py \
    --listen \
    --port "$FORGE_PORT" \
    --xformers \
    --enable-insecure-extension-access \
    --api \
    --no-half-vae \
    > "$LOGS_DIR/forge.log" 2>&1 &
FORGE_PID=$!
deactivate
log "Forge started (PID $FORGE_PID)"

# ---------------------------------------------------------------------------
# 6. Health check loop
# ---------------------------------------------------------------------------
log "============================================="
log "  Forge  → http://0.0.0.0:$FORGE_PORT"
log "  ComfyUI → http://0.0.0.0:$COMFYUI_PORT"
log "  Logs   → $LOGS_DIR/"
log "============================================="
log "Shared models directory: $MODELS_DIR/"
log "  checkpoints/ — Pony, SDXL, etc."
log "  loras/       — LoRA files"
log "  diffusion_models/ — WAN 2.2 UNet, etc."
log "  text_encoders/    — CLIP/T5 for WAN 2.2"
log "============================================="

# Keep container alive and monitor
while true; do
    if ! kill -0 $FORGE_PID 2>/dev/null; then
        log "WARNING: Forge process died. Check $LOGS_DIR/forge.log"
    fi
    if ! kill -0 $COMFY_PID 2>/dev/null; then
        log "WARNING: ComfyUI process died. Check $LOGS_DIR/comfyui.log"
    fi
    sleep 30
done
