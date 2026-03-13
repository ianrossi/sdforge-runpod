#!/bin/bash
# =============================================================================
# Thin-image startup — apps + Python packages live on the network volume.
#
# First boot  (~3 min): clone repos, create venv, pip install
# Warm boot   (~30 s) : activate cached venv, symlink models, launch
# =============================================================================
set -euo pipefail

NV="/workspace"
COMFYUI_DIR="$NV/comfyui"
VENV_DIR="$NV/venv"
MODELS_DIR="$NV/models"
OUTPUTS_DIR="$NV/outputs"
LOGS_DIR="$NV/logs"
COMFYUI_PORT="${COMFYUI_PORT:-8188}"
STAMP="$NV/.setup-complete"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# ── 0. SSH (RunPod injects PUBLIC_KEY) ──────────────────────────────────────
if [ -n "${PUBLIC_KEY:-}" ]; then
    mkdir -p ~/.ssh
    echo "$PUBLIC_KEY" > ~/.ssh/authorized_keys
    chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys
    /usr/sbin/sshd 2>/dev/null && log "sshd started" || log "sshd failed (non-fatal)"
fi

# ── 1. First-boot setup (installs to network volume) ───────────────────────
if [ ! -f "$STAMP" ]; then
    log "=== FIRST BOOT — installing to network volume ==="

    # Create directory structure
    mkdir -p "$MODELS_DIR"/{checkpoints,loras,vae,clip,controlnet,upscalers,embeddings}
    mkdir -p "$MODELS_DIR"/{diffusion_models,text_encoders}
    mkdir -p "$OUTPUTS_DIR"/comfyui
    mkdir -p "$LOGS_DIR"

    # Clone ComfyUI
    if [ ! -d "$COMFYUI_DIR" ]; then
        log "Cloning ComfyUI..."
        git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git "$COMFYUI_DIR"
    else
        log "ComfyUI already cloned, pulling latest..."
        cd "$COMFYUI_DIR" && git pull --ff-only 2>/dev/null || true
    fi

    # Clone ComfyUI-Manager
    MANAGER_DIR="$COMFYUI_DIR/custom_nodes/ComfyUI-Manager"
    if [ ! -d "$MANAGER_DIR" ]; then
        log "Cloning ComfyUI-Manager..."
        git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git "$MANAGER_DIR"
    fi

    # Create venv with --system-site-packages to inherit PyTorch + CUDA from base
    if [ ! -d "$VENV_DIR" ]; then
        log "Creating venv (inherits PyTorch from base image)..."
        python -m venv "$VENV_DIR" --system-site-packages
    fi

    # Install ComfyUI deps (only ones not already in the base image)
    log "Installing ComfyUI requirements..."
    "$VENV_DIR/bin/pip" install --no-cache-dir -r "$COMFYUI_DIR/requirements.txt" 2>&1 | tail -5

    # Install Manager deps
    if [ -f "$MANAGER_DIR/requirements.txt" ]; then
        log "Installing ComfyUI-Manager requirements..."
        "$VENV_DIR/bin/pip" install --no-cache-dir -r "$MANAGER_DIR/requirements.txt" 2>&1 | tail -5 || true
    fi

    touch "$STAMP"
    log "=== First-boot setup complete ==="
else
    log "Warm boot — using cached venv at $VENV_DIR"
    # Quick update check (non-blocking, best-effort)
    if [ -d "$COMFYUI_DIR/.git" ]; then
        cd "$COMFYUI_DIR" && git pull --ff-only 2>/dev/null || true
    fi
fi

# ── 2. Ensure model + output directories exist ─────────────────────────────
mkdir -p "$MODELS_DIR"/{checkpoints,loras,vae,clip,controlnet,upscalers,embeddings}
mkdir -p "$MODELS_DIR"/{diffusion_models,text_encoders}
mkdir -p "$OUTPUTS_DIR"/comfyui
mkdir -p "$LOGS_DIR"

# ── 3. Symlink ComfyUI model dirs → network volume ─────────────────────────
log "Linking model directories..."
declare -A COMFY_MAP=(
    ["checkpoints"]="checkpoints"
    ["loras"]="loras"
    ["vae"]="vae"
    ["clip"]="clip"
    ["controlnet"]="controlnet"
    ["upscale_models"]="upscalers"
    ["embeddings"]="embeddings"
    ["diffusion_models"]="diffusion_models"
    ["text_encoders"]="text_encoders"
)
for comfy_name in "${!COMFY_MAP[@]}"; do
    rm -rf "$COMFYUI_DIR/models/$comfy_name"
    ln -sfn "$MODELS_DIR/${COMFY_MAP[$comfy_name]}" "$COMFYUI_DIR/models/$comfy_name"
done
rm -rf "$COMFYUI_DIR/output"
ln -sfn "$OUTPUTS_DIR/comfyui" "$COMFYUI_DIR/output"

# ── 4. Launch ComfyUI ──────────────────────────────────────────────────────
log "Starting ComfyUI on :$COMFYUI_PORT ..."
log "  Models:  $MODELS_DIR/"
log "  Outputs: $OUTPUTS_DIR/comfyui/"
log "  Venv:    $VENV_DIR/"

cd "$COMFYUI_DIR"
exec "$VENV_DIR/bin/python" main.py \
    --listen 0.0.0.0 \
    --port "$COMFYUI_PORT" \
    --preview-method auto \
    2>&1 | tee "$LOGS_DIR/comfyui.log"
