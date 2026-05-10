#!/bin/bash
# Download AI models for Omi Omni
# Usage: ./scripts/download-models.sh

set -e

echo "=== Downloading AI Models ==="
echo ""

mkdir -p models/whisper models/llm

echo "Downloading Whisper medium model (1.4GB)..."
if command -v wget &> /dev/null; then
    wget -q --show-progress -O models/whisper/ggml-medium.bin https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin
elif command -v curl &> /dev/null; then
    curl -L -o models/whisper/ggml-medium.bin --progress-bar https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin
else
    echo "ERROR: Neither wget nor curl found. Please install one of them."
    exit 1
fi

echo ""
echo "Whisper model downloaded successfully!"
echo ""
echo "Note: Ollama models will be downloaded automatically when you start the backend."
echo "Common models: qwen2.5:3b, llama3.1:8b, mistral:7b"
