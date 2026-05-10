# Getting Started with Omi Omni

> **Omi Omni** is a self-hosted version of the Omi AI wearable application that brings full local capabilities to your Omi hardware.

This guide will walk you through setting up and using Omi Omni.

## 📋 Prerequisites

### Hardware Requirements

#### For Backend Server
- **GPU**: NVIDIA GPU with CUDA support **OR** AMD RX 7000 series (RX 7900 XTX recommended)
- **VRAM**: Minimum 16GB recommended (24GB for best performance)
- **RAM**: 32GB+ recommended
- **Storage**: 100GB+ SSD (for models and data)
- **OS**: Linux (Ubuntu 22.04 LTS recommended), Windows 11, or macOS

#### For Mobile App
- **Device**: iOS or Android smartphone
- **Bluetooth**: BLE 5.0+ support required
- **OS**: iOS 15+ or Android 8.0+

#### Omi Hardware
- Omi wearable device (any version)
- Charged battery

### Software Requirements

#### Backend Server
- [Docker](https://www.docker.com/) (v20.10+)
- [Docker Compose](https://docs.docker.com/compose/) (v2.0+)
- **For NVIDIA**: [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)
- **For AMD**: [ROCm](https://rocm.docs.amd.com/) (v5.6+)

#### Mobile App
- [Flutter SDK](https://flutter.dev/docs/get-started/install) (v3.0+)
- Android Studio or Xcode (for mobile development)

## 🚀 Installation

### Step 1: Clone the Repository

```bash
# Clone the repository
git clone https://github.com/yourusername/omi-omni.git
cd omi-omni
```

### Step 2: Configure Environment

#### For Backend
```bash
# Copy the example environment file
cp .env.example .env

# Edit the .env file with your configuration
nano .env
```

**Important Configuration Options:**
```bash
# Backend settings
BACKEND_PORT=8000
API_KEY=your-secure-api-key-here

# Database
POSTGRES_DB=omi
POSTGRES_USER=omi
POSTGRES_PASSWORD=your-postgres-password

# AI Models
WHISPER_MODEL=Systran/faster-whisper-large-v3
OLLAMA_MODEL=qwen2.5:14b

# For AMD GPUs (uncomment if using AMD)
# HSA_OVERRIDE_GFX_VERSION=10.3.0
```

#### For Mobile App
```bash
cd app
cp .env.example .env

# Edit the mobile app configuration
nano .env
```

**Mobile App Configuration:**
```bash
# Backend connection
API_BASE_URL=http://your-server-ip:8000
API_KEY=your-api-key-here

# Feature flags
ENABLE_AI_PROCESSING=true
ENABLE_OFFLINE_RECORDING=true
```

### Step 3: Choose Your GPU Configuration

#### For NVIDIA GPUs
```bash
# Use the standard docker-compose file
docker compose -f docker/docker-compose.yml up -d
```

#### For AMD GPUs (RX 7900 XTX, etc.)
```bash
# Use the AMD-specific compose file
docker compose -f docker/docker-compose-amd.yml up -d
```

### Step 4: Run Setup Script

```bash
# Run the setup script to initialize everything
bash scripts/setup.sh
```

This script will:
1. Check Docker installation
2. Detect your GPU type
3. Start all services
4. Download AI models
5. Initialize the database
6. Verify all services are running

### Step 5: Verify Installation

```bash
# Check backend health
curl http://localhost:8000/health

# You should see a response like:
# {"status": "healthy", "version": "0.1.0", "services": {...}, "timestamp": "..."}
```

## 📱 Mobile App Setup

### Android

```bash
cd app

# Install dependencies
flutter pub get

# Run the app
flutter run
```

### iOS

```bash
cd app

# Install dependencies
flutter pub get

# Open in Xcode
open ios/Runner.xcworkspace

# Run the app from Xcode
```

## 🎯 First Use

### 1. Connect to Backend

When you first open the mobile app:
1. The app will automatically try to connect to your backend
2. If connection fails, check that:
   - Your backend is running (`docker compose ps`)
   - The API_BASE_URL in your mobile .env is correct
   - Your API_KEY matches between backend and mobile app

### 2. Connect Your Omi Device

1. Make sure your Omi device is charged
2. In the app, tap the Bluetooth icon to scan for devices
3. Select your Omi device from the list
4. Wait for the connection to establish

### 3. Start Recording

#### Local Recording (Offline Mode)
1. Tap the "Start Recording" button
2. Speak into your Omi device
3. Tap "Stop Recording" when finished
4. The recording will be saved locally on your phone

#### Real-time AI Processing
1. Make sure backend is connected (green cloud icon in app bar)
2. Tap the "Start Streaming" button
3. Speak into your Omi device
4. Your audio will be streamed to the backend for real-time transcription
5. When you stop, the conversation will be processed and saved

### 4. View Your Conversations

1. Tap the "Conversations" tab in the bottom navigation
2. View your transcribed conversations
3. Tap on a conversation to see details, summary, action items, and key topics

### 5. Search Your Memories

1. Tap the "Memories" tab
2. Use the search bar to find specific information
3. Results will show semantic matches from your conversations

### 6. Chat with Your Data

1. Tap the "Chat" tab
2. Type your question
3. The AI will use your conversation history to provide context-aware answers

## 🔧 Configuration Options

### Backend Configuration

Edit `.env` in the root directory:

```bash
# Server ports
BACKEND_PORT=8000
WHISPER_PORT=8001
OLLAMA_PORT=11434
QDRANT_PORT=6333
POSTGRES_PORT=5432
MINIO_PORT=9000
REDIS_PORT=6379
MEILISEARCH_PORT=7700

# AI Models (choose based on your GPU)
# For 24GB VRAM (RX 7900 XTX):
WHISPER_MODEL=Systran/faster-whisper-large-v3
OLLAMA_MODEL=qwen2.5:32b

# For 16GB VRAM:
WHISPER_MODEL=Systran/faster-whisper-large-v3
OLLAMA_MODEL=qwen2.5:14b

# For 8GB VRAM:
WHISPER_MODEL=Systran/faster-whisper-medium
OLLAMA_MODEL=llama3.1:8b

# Performance tuning
WHISPER_COMPUTE_TYPE=float16
OLLAMA_MAX_LOADED_MODELS=2
OLLAMA_KEEP_ALIVE=24h
```

### Mobile App Configuration

Edit `app/.env`:

```bash
# Backend connection
API_BASE_URL=http://your-server-ip:8000
API_KEY=your-api-key-here

# Feature flags
ENABLE_AI_PROCESSING=true
ENABLE_OFFLINE_RECORDING=true
ENABLE_OTA_UPDATES=true

# Audio settings
AUDIO_CHUNK_SIZE=4096
MAX_RECORDING_DURATION=3600
AUDIO_CODEC=opus

# UI settings
USE_DARK_THEME=true
```

## 🎨 Model Recommendations

### For RX 7900 XTX (24GB VRAM)

| Whisper Model | LLM Model | Total VRAM | Quality | Speed |
|---------------|-----------|------------|---------|-------|
| Large-v3 | qwen2.5:32b | ~23GB | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| Large-v3 | qwen2.5:14b | ~13GB | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| Medium | qwen2.5:14b | ~11GB | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| Medium | llama3.1:8b | ~6.5GB | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |

**Recommended**: `Systran/faster-whisper-large-v3` + `qwen2.5:14b` (balanced)

### For RTX 4090 (24GB VRAM)

Same recommendations as RX 7900 XTX, but with slightly better performance due to CUDA optimization.

### For 16GB VRAM GPUs

| Whisper Model | LLM Model | Total VRAM | Quality | Speed |
|---------------|-----------|------------|---------|-------|
| Large-v3 | qwen2.5:14b | ~13GB | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| Medium | qwen2.5:14b | ~11GB | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| Medium | llama3.1:8b | ~6.5GB | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |

**Recommended**: `Systran/faster-whisper-large-v3` + `qwen2.5:14b`

### For 8GB VRAM GPUs

| Whisper Model | LLM Model | Total VRAM | Quality | Speed |
|---------------|-----------|------------|---------|-------|
| Medium | llama3.1:8b | ~6.5GB | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| Small | llama3.1:8b | ~4GB | ⭐⭐ | ⭐⭐⭐⭐⭐ |

**Recommended**: `Systran/faster-whisper-medium` + `llama3.1:8b`

## 🛠️ Troubleshooting

### Backend Won't Start

1. **Check Docker is running**: `docker --version`
2. **Check containers**: `docker compose ps`
3. **View logs**: `docker compose logs`
4. **Check ports**: Make sure ports 8000-8001, 11434, 5432, etc. are not in use

### GPU Not Detected

#### NVIDIA
1. Install NVIDIA Container Toolkit: `sudo apt install nvidia-container-toolkit`
2. Restart Docker: `sudo systemctl restart docker`
3. Verify: `docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi`

#### AMD
1. Install ROCm: Follow [AMD ROCm installation guide](https://rocm.docs.amd.com/)
2. Add user to render and video groups: `sudo usermod -aG render,video $USER`
3. Verify: `rocminfo`
4. Reboot after installation

### Mobile App Won't Connect to Backend

1. **Check API_BASE_URL**: Make sure it's correct in `app/.env`
2. **Check API_KEY**: Make sure it matches between backend and mobile app
3. **Check network**: Make sure your phone and server are on the same network
4. **Check firewall**: Make sure port 8000 is open on your server
5. **Test connection**: `curl http://your-server-ip:8000/health`

### Omi Device Won't Connect

1. **Check Bluetooth**: Make sure Bluetooth is enabled on your phone
2. **Check permissions**: Make sure location and Bluetooth permissions are granted
3. **Check battery**: Make sure your Omi device is charged
4. **Restart app**: Close and reopen the app
5. **Restart device**: Turn your Omi device off and on

### Audio Not Recording

1. **Check connection**: Make sure your Omi device is connected
2. **Check microphone**: Make sure the microphone on your Omi device is working
3. **Check permissions**: Make sure microphone permission is granted
4. **Test with another app**: Try using your Omi device with the official Omi app

## 📚 Next Steps

- [User Guide](user-guide.md) - Learn all features of Omi Omni
- [Troubleshooting](troubleshooting.md) - Common issues and solutions
- [FAQ](faq.md) - Frequently asked questions

## 🙏 Support

If you're still having issues:
1. Check the [Troubleshooting Guide](troubleshooting.md)
2. Look through the [FAQ](faq.md)
3. Open an issue on GitHub with details about your setup and the error

---

**Welcome to Omi Omni!** Your Omi, Your Data, Your Control
