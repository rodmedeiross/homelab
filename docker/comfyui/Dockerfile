# ai-dock/comfyui base + PyTorch cu128 for Blackwell GPUs (RTX 50-series, sm_120).
# Stopgap until ai-dock publishes a CUDA 12.8+ tag.

FROM ghcr.io/ai-dock/comfyui:latest-cuda

ARG TORCH_VERSION=2.11.0
ARG TORCHVISION_VERSION=0.26.0
ARG TORCHAUDIO_VERSION=2.11.0

RUN /opt/environments/python/comfyui/bin/pip install --no-cache-dir --upgrade \
      --index-url https://download.pytorch.org/whl/cu128 \
      torch==${TORCH_VERSION} \
      torchvision==${TORCHVISION_VERSION} \
      torchaudio==${TORCHAUDIO_VERSION}
