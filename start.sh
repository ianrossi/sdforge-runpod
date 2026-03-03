#!/bin/bash
# =============================================================================
# Lightweight startup — everything is pre-installed in the image.
# Only creates NV dirs, symlinks models, and launches services.
# Typical boot: ~15-30 seconds.
# =============================================================================
set -euo pipefail

NV="/workspace"
MODELS_DIR="$NV/models"
OUTPUTS_DIR="$NV/outputs"
LOGS_DIR="$NV/logs"

FORGE_PORT="${FORGE_PORT:-7860}"
COMFYUI_PORT="${COMFYUI_PORT:-8188}"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# ── 1. Create NV directories (idempotent) ────────────────────────────────────
log "Preparing network volume directories..."
mkdir -p "$MODELS_DIR"/{checkpoints,loras,vae,clip,controlnet,upscalers,embeddings}
mkdir -p "$MODELS_DIR"/{diffusion_models,text_encoders}
mkdir -p "$OUTPUTS_DIR"/{forge,comfyui}
mkdir -p "$LOGS_DIR"

# ── 2. Symlink Forge model dirs → NV ─────────────────────────────────────────
log "Linking Forge model directories..."
declare -A FORGE_MAP=(
    ["Stable-diffusion"]="checkpoints"
    ["Lora"]="loras"
    ["VAE"]="vae"
    ["ControlNet"]="controlnet"
    ["ESRGAN"]="upscalers"
)
for forge_name in "${!FORGE_MAP[@]}"; do
    mkdir -p /opt/forge/models
    ln -sfn "$MODELS_DIR/${FORGE_MAP[$forge_name]}" "/opt/forge/models/$forge_name"
done
ln -sfn "$MODELS_DIR/embeddings" /opt/forge/embeddings
ln -sfn "$OUTPUTS_DIR/forge"     /opt/forge/outputs

# ── 3. Symlink ComfyUI model dirs → NV ───────────────────────────────────────
log "Linking ComfyUI model directories..."
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
    mkdir -p /opt/comfyui/models
    ln -sfn "$MODELS_DIR/${COMFY_MAP[$comfy_name]}" "/opt/comfyui/models/$comfy_name"
done
ln -sfn "$OUTPUTS_DIR/comfyui" /opt/comfyui/output

# ── 4. Start ComfyUI ─────────────────────────────────────────────────────────
log "Starting ComfyUI on :$COMFYUI_PORT ..."
cd /opt/comfyui
python main.py \
    --listen 0.0.0.0 \
    --port "$COMFYUI_PORT" \
    --preview-method auto \
    > "$LOGS_DIR/comfyui.log" 2>&1 &
COMFY_PID=$!

# ── 5. Start Forge ───────────────────────────────────────────────────────────
log "Starting Forge on :$FORGE_PORT ..."
cd /opt/forge
python launch.py \
    --listen \
    --port "$FORGE_PORT" \
    --xformers \
    --enable-insecure-extension-access \
    --api \
    --no-half-vae \
    > "$LOGS_DIR/forge.log" 2>&1 &
FORGE_PID=$!

# ── 6. Banner ─────────────────────────────────────────────────────────────────
log "============================================="
log "  Forge   → http://0.0.0.0:$FORGE_PORT"
log "  ComfyUI → http://0.0.0.0:$COMFYUI_PORT"
log "============================================="
log "Shared models: $MODELS_DIR/"
log "  checkpoints/       — Pony, SDXL checkpoints"
log "  loras/             — LoRA files"
log "  diffusion_models/  — WAN 2.2 UNet, etc."
log "  text_encoders/     — CLIP / T5 for WAN 2.2"
log "============================================="

# ── 7. Keep alive + health monitor ───────────────────────────────────────────
while true; do
    for name_pid in "Forge:$FORGE_PID" "ComfyUI:$COMFY_PID"; do
        svc="${name_pid%%:*}"
        pid="${name_pid##*:}"
        if ! kill -0 "$pid" 2>/dev/null; then
            log "WARNING: $svc (PID $pid) died — check $LOGS_DIR/"
        fi
    done
    sleep 30
done
