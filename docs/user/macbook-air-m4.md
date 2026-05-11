# MacBook Air M4 Setup Guide

This guide covers setting up Omi Omni on a **MacBook Air with M4 chip** (or any Apple Silicon Mac).

## 🎯 Quick Start (Lightweight Mode)

The M4 MacBook Air has limited RAM (typically 8GB-16GB), so we use lightweight models:

```bash
# 1. Clone the repository
git clone https://github.com/indubitablyodin/omi-omni.git
cd omi-omni

# 2. Download lightweight Whisper model (300MB)
./scripts/download-models.sh small

# 3. Start with Mac configuration
make start-mac
```

Backend will be available at: `http://127.0.0.1:8002`

**Important:** Host-published ports are different from container ports:
- Backend: container port 8000, host port 8002
- Whisper: container port 9000, host port 8001
- MinIO: container port 9000, host port 9000

Inside the Docker Compose network, services communicate using container ports:
- Backend talks to Whisper at `whisper:9000`
- Backend talks to MinIO at `minio:9000`

## 📊 Resource Configuration

| Component | M4 Configuration | RAM Usage | Notes |
|-----------|-----------------|-----------|-------|
| Whisper | `faster-whisper-small` | ~500MB | Good accuracy, fast |
| LLM | `qwen2.5:0.5b` | ~1GB | Lightweight, capable |
| PostgreSQL | Alpine | ~100MB | Minimal overhead |
| Qdrant | Standard | ~200MB | Vector database |
| MinIO | Standard | ~100MB | Audio storage |
| Redis | Alpine | ~50MB | Cache |
| Meilisearch | Standard | ~150MB | Search |
| **Total** | | **~2-3GB** | All services |

## 🎛️ Model Tiers

Omi Omni supports different model tiers for different hardware:

### Lightweight (Recommended for M4 MacBook Air)
```bash
MODEL_TIER=lightweight
WHISPER_MODEL=Systran/faster-whisper-small
LLM_MODEL=qwen2.5:0.5b
```
- **RAM Usage:** ~2-3GB
- **Quality:** Good
- **Speed:** Fast

### Balanced
```bash
MODEL_TIER=balanced
WHISPER_MODEL=Systran/faster-whisper-medium
LLM_MODEL=qwen2.5:1.5b
```
- **RAM Usage:** ~4-5GB
- **Quality:** Very Good
- **Speed:** Medium

### High Quality (Not recommended for 8GB RAM)
```bash
MODEL_TIER=high
WHISPER_MODEL=Systran/faster-whisper-large-v3
LLM_MODEL=llama3.1:8b
```
- **RAM Usage:** ~8-10GB
- **Quality:** Excellent
- **Speed:** Slow

## 🚀 Apple Silicon Optimizations

### Native ARM64 Support
All Docker images used in `docker-compose-mac.yml` support ARM64:
- ✅ `postgres:16-alpine` - ARM64 compatible
- ✅ `qdrant/qdrant:latest` - ARM64 compatible
- ✅ `minio/minio:latest` - ARM64 compatible
- ✅ `redis:7-alpine` - ARM64 compatible
- ✅ `getmeili/meilisearch:latest` - ARM64 compatible
- ✅ `ollama/ollama:latest` - ARM64 compatible with Metal acceleration
- ✅ `ghcr.io/cocktailpeanut/faster-whisper:latest` - ARM64 compatible

### Metal Acceleration
Ollama automatically uses Apple's Metal API for GPU acceleration on M4. No additional configuration needed!

## 📝 Configuration

### Environment Variables

Edit `.env` or use `.env.mac` as a template:

```bash
# Copy the Mac template
cp .env.mac .env

# Edit with your preferred editor
nano .env
# or
code .env
```

### Key Settings for M4:
```bash
# Use lightweight models
MODEL_TIER=lightweight
WHISPER_MODEL=Systran/faster-whisper-small
LLM_MODEL=qwen2.5:0.5b

# Limit resource usage
OLLAMA_MAX_VRAM=2gb
OLLAMA_MAX_LOADED_MODELS=1

# Use CPU for Whisper (Metal acceleration via Ollama)
WHISPER__DEVICE=cpu
WHISPER__COMPUTE_TYPE=int8
```

## 🔧 Troubleshooting

### Docker Desktop for Apple Silicon
Ensure you have Docker Desktop installed and running:
1. Download from: https://www.docker.com/products/docker-desktop/
2. Enable Rosetta in Docker Desktop settings (for x86_64 emulation if needed)

### Out of Memory Errors
If you get OOM errors:
1. Reduce `OLLAMA_MAX_LOADED_MODELS` to `1`
2. Use smaller models:
   ```bash
   WHISPER_MODEL=Systran/faster-whisper-tiny
   LLM_MODEL=phi3:3.8b-mini
   ```
3. Stop other memory-intensive applications

### Slow Performance
- Ensure Docker has enough resources allocated (Settings > Resources)
- Use `int8` quantization for Whisper:
  ```bash
  WHISPER__COMPUTE_TYPE=int8
  ```

## 📁 File Structure

```
omi-omni/
├── docker/
│   ├── docker-compose-mac.yml    # Mac-specific configuration
│   └── Dockerfile.whisper-amd    # AMD GPU build (not used on Mac)
├── .env.mac                      # Mac environment template
└── scripts/
    └── download-models.sh        # Download Whisper models
```

## 🎯 Commands Summary

| Command | Description |
|---------|-------------|
| `make start-mac` | Start all services with Mac configuration |
| `make stop` | Stop all services |
| `make restart` | Restart all services |
| `make clean` | Remove containers and volumes |
| `make apk` | Build Android APK |

## 🧪 Smoke Test

Run the complete smoke test to verify your setup:

```bash
./scripts/smoke-mac.sh
```

This will:
1. Validate docker compose configuration
2. Start all services
3. Check container status
4. Test backend health (http://127.0.0.1:8002/health)
5. Test Whisper server (http://127.0.0.1:8001/v1/models)
6. Check backend logs for errors

The script fails loudly if backend health check fails.

## 🔗 Related Issues

- [#9](https://github.com/indubitablyodin/omi-omni/issues/9) - Add lightweight profile for MacBook Air / low-RAM deployments
- [#10](https://github.com/indubitablyodin/omi-omni/issues/10) - Add model tier configuration for STT and LLM based on available RAM
- [#11](https://github.com/indubitablyodin/omi-omni/issues/11) - Support Apple Silicon optimized transcription backend
- [#16](https://github.com/indubitablyodin/omi-omni/issues/16) - Document MacBook Air M4 setup guide
