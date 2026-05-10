#!/bin/bash
# Download AI models for Omi Omni
# Usage: ./scripts/download-models.sh [model-size]
#   model-size: tiny, small, medium, large (default: medium)

set -e

MODEL_SIZE=${1:-medium}

echo "=== Downloading AI Models ($MODEL_SIZE) ==="
echo ""

mkdir -p models/whisper models/llm

# Model URLs
case $MODEL_SIZE in
    tiny)
        MODEL_FILE="ggml-tiny.bin"
        MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin"
        MODEL_NAME="tiny"
        ;;
    small)
        MODEL_FILE="ggml-small.bin"
        MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"
        MODEL_NAME="small"
        ;;
    medium)
        MODEL_FILE="ggml-medium.bin"
        MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin"
        MODEL_NAME="medium"
        ;;
    large)
        MODEL_FILE="ggml-large-v3.bin"
        MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin"
        MODEL_NAME="large-v3"
        ;;
    *)
        echo "Invalid model size: $MODEL_SIZE"
        echo "Valid options: tiny, small, medium, large"
        exit 1
        ;;
esac

echo "Downloading Whisper $MODEL_NAME model..."

if command -v wget &> /dev/null; then
    wget -q --show-progress -O models/whisper/$MODEL_FILE $MODEL_URL
elif command -v curl &> /dev/null; then
    curl -L -o models/whisper/$MODEL_FILE --progress-bar $MODEL_URL
else
    echo "ERROR: Neither wget nor curl found. Please install one of them."
    exit 1
fi

echo ""
echo "Whisper $MODEL_NAME model downloaded successfully!"
echo ""

# Create symlink for compatibility
if [ ! -f models/whisper/ggml-medium.bin ] && [ $MODEL_SIZE != "medium" ]; then
    ln -sf models/whisper/$MODEL_FILE models/whisper/ggml-medium.bin
    echo "Created symlink: ggml-medium.bin -> $MODEL_FILE"
fi

echo ""
echo "Note: Ollama models will be downloaded automatically when you start the backend."
echo ""
echo "Recommended Ollama models by hardware:"
echo "  MacBook Air M4 (8GB RAM): qwen2.5:0.5b, phi3:3.8b-mini"
echo "  MacBook Air M4 (16GB RAM): qwen2.5:1.5b, llama3.1:8b"
echo "  AMD RX 7900 XTX (24GB VRAM): qwen2.5:7b, llama3.1:70b"
