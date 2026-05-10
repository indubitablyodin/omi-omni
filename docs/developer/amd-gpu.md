# AMD GPU Setup Guide for Omi Omni

This guide provides detailed instructions for setting up Omi Omni with AMD GPUs, specifically targeting the RX 7900 XTX and other RX 7000 series cards.

## 🎯 Overview

Omi Omni supports both NVIDIA and AMD GPUs for AI inference. While NVIDIA GPUs use CUDA, AMD GPUs use ROCm (Radeon Open Compute) for GPU acceleration.

### Supported AMD GPUs
- **RX 7000 Series**: RX 7900 XTX, RX 7900 XT, RX 7800 XT, RX 7700 XT, etc.
- **RX 6000 Series**: RX 6950 XT, RX 6900 XT, RX 6800 XT, etc. (limited support)
- **Radeon Pro**: W7900, W7800, etc.

### Requirements
- **ROCm Version**: 5.6+ (recommended: 6.0+)
- **Linux OS**: Ubuntu 22.04 LTS (recommended)
- **Kernel**: 5.15+ (for RX 7000 series)
- **VRAM**: 16GB+ recommended (24GB for best experience)

## 🛠️ System Preparation

### Step 1: Check System Compatibility

```bash
# Check CPU architecture
uname -m
# Should output: x86_64

# Check kernel version
uname -r
# Should be 5.15 or higher for RX 7000 series

# Check if you have an AMD GPU
lspci | grep -i amd
# Should show your AMD GPU
```

### Step 2: Install ROCm

#### For Ubuntu 22.04

```bash
# Add ROCm repository
sudo apt update && sudo apt install -y wget
wget -q -O - https://repo.radeon.com/rocm/rocm.key | gpg --dearmor -o /usr/share/keyrings/rocm-archive-keyring.gpg

echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/rocm-archive-keyring.gpg] https://repo.radeon.com/rocm/apt/6.0 jammy main' | sudo tee /etc/apt/sources.list.d/rocm.list

# Install ROCm
sudo apt update
sudo apt install -y rocm-opencl-runtime rocm-hip-sdk

# Add user to render and video groups
sudo usermod -aG render,video $USER

# Reboot to apply changes
sudo reboot
```

#### For Other Linux Distributions

Follow the official ROCm installation guide for your distribution:
- [ROCm Documentation](https://rocm.docs.amd.com/)

### Step 3: Verify ROCm Installation

```bash
# Check ROCm version
rocm-smi

# Check if GPU is detected
rocminfo

# Check HIP version
hipconfig
```

You should see your AMD GPU listed with its VRAM and other details.

### Step 4: Install ROCm Aware Docker

```bash
# Install Docker
sudo apt install -y docker.io docker-compose-plugin

# Add user to docker group
sudo usermod -aG docker $USER

# Install ROCm Docker support
sudo apt install -y rocm-dkms

# Configure Docker to use ROCm
sudo usermod -aG docker $USER
newgrp docker
```

### Step 5: Set Environment Variables

Add these to your `~/.bashrc` or `~/.zshrc`:

```bash
# ROCm environment variables
export ROCM_PATH=/opt/rocm
export HIP_PATH=/opt/rocm
export HSA_OVERRIDE_GFX_VERSION=10.3.0  # For RX 7900 XTX

# For RX 7900 XTX specifically
export HSA_OVERRIDE_GFX_VERSION=10.3.0

# Apply changes
source ~/.bashrc
```

**Note**: The `HSA_OVERRIDE_GFX_VERSION` is crucial for RX 7000 series GPUs. Different values for different GPUs:
- RX 7900 XTX: `10.3.0`
- RX 7900 XT: `10.3.0`
- RX 7800 XT: `10.3.0`
- RX 7700 XT: `10.3.0`
- RX 6950 XT: `10.3.0`

## 🚀 Omi Omni Configuration for AMD

### Step 1: Use AMD-Specific Docker Compose

Omi Omni provides a separate docker-compose file for AMD GPUs:

```bash
# Use the AMD-specific compose file
docker compose -f docker/docker-compose-amd.yml up -d
```

### Step 2: Configure Environment Variables

Edit your `.env` file:

```bash
# AMD-specific settings
HSA_OVERRIDE_GFX_VERSION=10.3.0
ROCM_PATH=/opt/rocm
HIP_PATH=/opt/rocm

# Model selection for RX 7900 XTX (24GB VRAM)
WHISPER_MODEL=Systran/faster-whisper-large-v3
OLLAMA_MODEL=qwen2.5:14b
WHISPER_COMPUTE_TYPE=float16
```

### Step 3: Model Recommendations for RX 7900 XTX

| Whisper Model | VRAM Usage | LLM Model | VRAM Usage | Total | Fit? |
|---------------|------------|-----------|------------|-------|------|
| Large-v3 | ~3GB | qwen2.5:32b | ~20GB | ~23GB | ✅ Yes |
| Large-v3 | ~3GB | qwen2.5:14b | ~10GB | ~13GB | ✅ Yes |
| Large-v3 | ~3GB | llama3.1:8b | ~5GB | ~8GB | ✅ Yes |
| Medium | ~1.5GB | qwen2.5:32b | ~20GB | ~21.5GB | ✅ Yes |
| Medium | ~1.5GB | qwen2.5:14b | ~10GB | ~11.5GB | ✅ Yes |

**Recommended for RX 7900 XTX**:
- **Best Quality**: Large-v3 + qwen2.5:32b (~23GB)
- **Balanced**: Large-v3 + qwen2.5:14b (~13GB)
- **Best Performance**: Medium + llama3.1:8b (~6.5GB)

### Step 4: Start Services

```bash
# Navigate to the repository root
cd omi-omni

# Start all services with AMD configuration
docker compose -f docker/docker-compose-amd.yml up -d

# Monitor the startup process
docker compose -f docker/docker-compose-amd.yml logs -f
```

## 🔍 Verification

### Check GPU Detection in Containers

```bash
# Check Whisper container
docker exec -it omi-omni-whisper bash -c "rocminfo | head -20"

# Check Ollama container
docker exec -it omi-omni-ollama bash -c "rocminfo | head -20"
```

Both should show your AMD GPU information.

### Test Model Loading

```bash
# Test Whisper model loading
curl -X POST http://localhost:8001/v1/audio/transcriptions \
  -F file=@/dev/null \
  -F model=Systran/faster-whisper-large-v3

# Test Ollama model loading
curl -X POST http://localhost:11434/api/pull \
  -H "Content-Type: application/json" \
  -d '{"name": "qwen2.5:14b"}'
```

### Check Backend Health

```bash
curl http://localhost:8000/health
```

You should see all services reporting as healthy.

## ⚡ Performance Optimization

### ROCm-Specific Optimizations

#### 1. Set GPU Affinity

```bash
# Set which GPU to use (for multi-GPU systems)
export HIP_VISIBLE_DEVICES=0  # Use first GPU
export ROCR_VISIBLE_DEVICES=0
```

#### 2. Tune HIP Parameters

```bash
# Enable HIP profiling
export HIP_PROFILE_API=1

# Set HIP memory allocation strategy
export HIP_MEMORY_ALLOCATION_STRATEGY=aggressive
```

#### 3. Optimize for RX 7900 XTX

The RX 7900 XTX has 24GB of VRAM and excellent compute performance. For best results:

```bash
# Use float16 for faster inference with minimal quality loss
WHISPER_COMPUTE_TYPE=float16

# Keep models loaded for faster subsequent requests
OLLAMA_KEEP_ALIVE=24h
OLLAMA_MAX_LOADED_MODELS=2
```

### Memory Management

```bash
# Limit Docker memory usage (optional)
docker update --memory=24g omi-omni-whisper
docker update --memory=20g omi-omni-ollama
```

## 🛠️ Troubleshooting AMD-Specific Issues

### Issue 1: ROCm Not Detected in Docker

**Symptoms**: Containers fail to start or don't detect GPU

**Solutions**:

1. **Check device permissions**:
   ```bash
   ls -l /dev/kfd /dev/dri
   ```
   Both should be readable by your user.

2. **Add user to groups**:
   ```bash
   sudo usermod -aG render,video,docker $USER
   newgrp render
   newgrp video
   newgrp docker
   ```

3. **Check Docker device access**:
   ```bash
   docker run --rm --device /dev/kfd --device /dev/dri --group-add render --group-add video \
     rocm/rocm-terminal rocminfo
   ```

4. **Reboot**: Sometimes a reboot is needed after ROCm installation.

### Issue 2: Model Loading Failures

**Symptoms**: Models fail to load or download

**Solutions**:

1. **Check VRAM**: Make sure you have enough VRAM for the selected models.
2. **Try smaller models**: Switch to smaller models if you're running out of VRAM.
3. **Check ROCm version**: Some models may require specific ROCm versions.
4. **Manual model download**: Download models manually and place them in the correct directories.

### Issue 3: Slow Performance

**Symptoms**: Inference is slower than expected

**Solutions**:

1. **Use float16**: Set `WHISPER_COMPUTE_TYPE=float16` for faster inference.
2. **Reduce model size**: Use smaller models if acceptable.
3. **Check GPU utilization**:
   ```bash
   watch -n 1 rocm-smi
   ```
4. **Check CPU bottlenecks**: ROCm may be CPU-bound for some operations.

### Issue 4: Container Permission Issues

**Symptoms**: Permission denied errors when accessing devices

**Solutions**:

1. **Check group membership**:
   ```bash
   groups
   ```
   Should include `render`, `video`, and `docker`.

2. **Restart Docker**:
   ```bash
   sudo systemctl restart docker
   ```

3. **Check device permissions**:
   ```bash
   sudo chmod 666 /dev/kfd
   sudo chmod 666 /dev/dri/*
   ```

### Issue 5: HSA_OVERRIDE_GFX_VERSION Errors

**Symptoms**: Errors related to GFX version

**Solutions**:

1. **Try different versions**:
   ```bash
   # For RX 7900 XTX
   export HSA_OVERRIDE_GFX_VERSION=10.3.0
   
   # For RX 7800 XT
   export HSA_OVERRIDE_GFX_VERSION=10.3.0
   
   # For RX 6950 XT
   export HSA_OVERRIDE_GFX_VERSION=10.3.0
   ```

2. **Check your GPU's GFX version**:
   ```bash
   rocm-smi --showproductname
   ```

3. **Find the correct version**: Check AMD documentation for your specific GPU.

## 📊 Performance Benchmarks

### RX 7900 XTX Performance (24GB VRAM)

| Task | Model | Time (NVIDIA RTX 4090) | Time (RX 7900 XTX) | Notes |
|------|-------|-------------------------|---------------------|-------|
| Transcribe 1 min audio | Large-v3 | ~8s | ~10-12s | ROCm overhead |
| Generate 500 tokens | qwen2.5:14b | ~5s | ~6-7s | Good |
| Generate 500 tokens | llama3.1:8b | ~3s | ~4-5s | Good |
| Embedding | nomic-embed-text | ~1s | ~1-2s | Minimal overhead |

### VRAM Usage

| Model | VRAM Usage |
|-------|-------------|
| faster-whisper-large-v3 | ~3GB |
| faster-whisper-medium | ~1.5GB |
| qwen2.5:32b | ~20GB |
| qwen2.5:14b | ~10GB |
| llama3.1:8b | ~5GB |
| nomic-embed-text | ~300MB |

## 🎯 Recommended Configurations

### For RX 7900 XTX (24GB VRAM)

```bash
# .env configuration
WHISPER_MODEL=Systran/faster-whisper-large-v3
OLLAMA_MODEL=qwen2.5:14b
WHISPER_COMPUTE_TYPE=float16
OLLAMA_MAX_LOADED_MODELS=2
OLLAMA_KEEP_ALIVE=24h
HSA_OVERRIDE_GFX_VERSION=10.3.0
```

### For RX 7900 XT (20GB VRAM)

```bash
# .env configuration
WHISPER_MODEL=Systran/faster-whisper-large-v3
OLLAMA_MODEL=qwen2.5:14b
WHISPER_COMPUTE_TYPE=float16
OLLAMA_MAX_LOADED_MODELS=2
OLLAMA_KEEP_ALIVE=24h
HSA_OVERRIDE_GFX_VERSION=10.3.0
```

### For RX 7800 XT (16GB VRAM)

```bash
# .env configuration
WHISPER_MODEL=Systran/faster-whisper-large-v3
OLLAMA_MODEL=llama3.1:8b
WHISPER_COMPUTE_TYPE=float16
OLLAMA_MAX_LOADED_MODELS=2
OLLAMA_KEEP_ALIVE=24h
HSA_OVERRIDE_GFX_VERSION=10.3.0
```

## 🔄 Updating ROCm

```bash
# Update ROCm
sudo apt update
sudo apt upgrade -y rocm-opencl-runtime rocm-hip-sdk

# Reboot
sudo reboot

# Verify
rocm-smi
```

## 📚 Additional Resources

- [ROCm Documentation](https://rocm.docs.amd.com/)
- [ROCm GitHub](https://github.com/RadeonOpenCompute/ROCm)
- [AMD GPU Open](https://gpuopen.com/)
- [HIP Documentation](https://rocm.docs.amd.com/projects/HIP/en/latest/)

## 🙏 Support

If you're experiencing issues with AMD GPU setup:
1. Check the [Troubleshooting](#-troubleshooting-amd-specific-issues) section above
2. Verify your ROCm installation with `rocm-smi`
3. Check Docker logs: `docker compose -f docker/docker-compose-amd.yml logs`
4. Open an issue on GitHub with your system details and error messages

---

**Omi Omni with AMD RX 7900 XTX** - Full local AI processing with excellent performance
