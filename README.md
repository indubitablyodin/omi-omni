# Omi Omni

> **Omi Omni** is a fork of the Omi AI application that brings **full local capabilities** to the Omi hardware while retaining advanced functionality.

This unified repository combines:
- ✅ **Mobile App** (Flutter) - Cross-platform Omi device interface
- ✅ **Firmware** (Zephyr RTOS) - Omi wearable device firmware
- ✅ **Self-Hosted Backend** (FastAPI) - Local AI processing pipeline
- ✅ **AMD/ROCm Support** - Full compatibility with AMD GPUs (RX 7900 XTX, etc.)

## 🎯 Project Vision

Omi Omni eliminates cloud dependencies by providing a complete local ecosystem:

```
Omi Device → (BLE) → Flutter App → (WebSocket) → Local Backend
                                                      │
                                    ┌─────────────────┼─────────────────┐
                                    │                 │                 │
                              Faster Whisper    Ollama          PostgreSQL
                              (speech-to-text)   (LLM)          (database)
                                    │                 │                 │
                                    │            Qdrant            MinIO
                                    │          (vectors)        (audio files)
                                    │                                  │
                                  Redis                         Meilisearch
                                 (cache)                         (search)
```

## 🚀 Key Features

### Mobile App (Flutter)
- **BLE Device Discovery** - Automatic scanning and connection to Omi devices
- **Real-time Audio Streaming** - Live audio capture with Opus/PCM codec support
- **Offline Recording** - Save recordings locally when disconnected
- **Firmware OTA Updates** - Over-the-air firmware updates
- **Button Controls** - Configurable single/double/triple tap gestures
- **Cross-Platform** - iOS, Android, macOS, Windows, Linux

### Backend Services
- **WebSocket Audio Ingestion** - Real-time audio streaming from mobile app
- **Speech-to-Text** - Faster Whisper with local processing
- **LLM Inference** - Ollama for local AI responses, summaries, and analysis
- **Vector Database** - Qdrant for semantic memory search
- **Object Storage** - MinIO for audio file storage
- **Structured Data** - PostgreSQL for conversations and metadata
- **Caching** - Redis for session management
- **Full-Text Search** - Meilisearch for fast text queries

### Hardware Support
- **NVIDIA GPUs** - Full CUDA support
- **AMD GPUs** - Complete ROCm support (RX 7000 series, including XTX)
- **CPU-Only** - Fallback mode for development/testing

## 📦 Repository Structure

```
omi-omni/
├── app/                    # Flutter mobile application
│   ├── lib/                # Dart source code
│   │   ├── backend/        # Backend schema and API clients
│   │   ├── providers/      # State management (Provider)
│   │   ├── services/       # Device services, audio processing
│   │   ├── screens/        # UI screens
│   │   ├── utils/          # Utilities (audio, firmware)
│   │   └── models/         # Data models
│   ├── android/            # Android platform code
│   ├── ios/                # iOS platform code
│   ├── firmware/           # Firmware assets
│   └── pubspec.yaml        # Flutter dependencies
│
├── backend/                # FastAPI backend server
│   ├── main.py             # FastAPI application
│   ├── config.py           # Configuration management
│   ├── database.py         # Database models and connections
│   ├── services.py         # Service clients (Whisper, Ollama, etc.)
│   ├── models/             # Pydantic models
│   ├── routes/             # API route handlers
│   └── Dockerfile          # Backend container
│
├── firmware/               # Zephyr RTOS firmware
│   ├── omi/                # Omi device firmware
│   │   ├── src/            # Source files
│   │   ├── CMakeLists.txt  # CMake configuration
│   │   └── prj.conf        # Zephyr project configuration
│   └── test/               # Test firmware
│
├── docker/                 # Docker configurations
│   ├── docker-compose.yml  # Main compose file (NVIDIA)
│   ├── docker-compose-amd.yml  # AMD/ROCm compose file
│   └── Dockerfile.*        # Service-specific Dockerfiles
│
├── scripts/                # Utility scripts
│   ├── setup.sh            # Initial setup and model download
│   ├── test.sh             # Test suite
│   ├── build-firmware.sh   # Firmware build script
│   └── deploy.sh           # Deployment helper
│
├── docs/                   # Documentation
│   ├── user/               # User guides
│   ├── developer/          # Development documentation
│   └── api/                # API documentation
│
├── .env.example            # Environment template
├── .gitignore              # Git ignore rules
├── README.md               # This file
└── LICENSE                 # License file
```

## 🛠️ Quick Start

### Prerequisites

#### For Mobile App Development
- Flutter SDK (latest stable)
- Android Studio / Xcode (for mobile development)
- Docker (for firmware building)

#### For Backend Deployment
- Docker & Docker Compose
- **For NVIDIA**: NVIDIA Container Toolkit, CUDA drivers
- **For AMD**: ROCm, HIP SDK
- Minimum 24GB VRAM recommended for full functionality
- 32GB+ RAM
- 100GB+ disk space

### 1. Clone and Configure

```bash
# Clone the repository
git clone https://github.com/yourusername/omi-omni.git
cd omi-omni

# Copy environment template
cp .env.example .env

# Edit .env with your configuration
nano .env
```

### 2. Choose Your GPU Configuration

#### For NVIDIA GPUs:
```bash
# Use the standard docker-compose
docker compose -f docker/docker-compose.yml up -d
```

#### For AMD GPUs (RX 7900 XTX, etc.):
```bash
# Use the AMD-specific compose file
docker compose -f docker/docker-compose-amd.yml up -d
```

### 3. Setup and Download Models

```bash
# Run setup script to download models and initialize database
bash scripts/setup.sh
```

### 4. Run the Mobile App

```bash
cd app
flutter pub get
flutter run
```

### 5. Build Firmware (Optional)

```bash
# Using Docker (recommended)
cd firmware/omi
./scripts/build-docker.sh

# The firmware package will be at:
# firmware/omi/build/docker_build/zephyr.zip
```

## 🔧 Configuration

### Environment Variables (.env)

```bash
# Backend Configuration
BACKEND_PORT=8000
API_KEY=your-secure-api-key-here

# Database
POSTGRES_DB=omi
POSTGRES_USER=omi
POSTGRES_PASSWORD=your-postgres-password
POSTGRES_PORT=5432

# Whisper (Speech-to-Text)
WHISPER_PORT=8001
WHISPER_MODEL=Systran/faster-whisper-large-v3
# For AMD: WHISPER_COMPUTE_TYPE=float16

# Ollama (LLM)
OLLAMA_PORT=11434
OLLAMA_MODEL=qwen2.5:14b  # Recommended for 24GB VRAM

# Vector Database (Qdrant)
QDRANT_PORT=6333
QDRANT_API_KEY=your-qdrant-api-key
QDRANT_COLLECTION=memories

# Object Storage (MinIO)
MINIO_PORT=9000
MINIO_CONSOLE_PORT=9001
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=your-minio-password
MINIO_BUCKET_AUDIO=omi-audio

# Cache (Redis)
REDIS_PORT=6379
REDIS_PASSWORD=your-redis-password

# Search (Meilisearch)
MEILISEARCH_PORT=7700
MEILISEARCH_KEY=your-meilisearch-key

# AMD-specific (if using AMD GPU)
HSA_OVERRIDE_GFX_VERSION=10.3.0
ROCM_PATH=/opt/rocm
```

### Mobile App Configuration

In `app/.env`:
```bash
# Backend connection
API_BASE_URL=http://your-server-ip:8000
API_KEY=your-api-key-here

# Feature flags
ENABLE_AI_PROCESSING=true
ENABLE_OFFLINE_RECORDING=true
ENABLE_OTA_UPDATES=true
```

## 📡 API Endpoints

### Health Check
```bash
curl http://localhost:8000/health
```

### WebSocket Audio Stream
```
ws://localhost:8000/ws/audio
```
Send raw audio bytes. On disconnect, the server processes the full conversation.

### REST API

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/v1/conversations` | List all conversations |
| GET | `/v1/conversations/{id}` | Get conversation details |
| GET | `/v1/memories` | List memories |
| GET | `/v1/memories/search?q={query}` | Semantic memory search |
| POST | `/v1/chat` | Chat with conversation history |
| POST | `/v1/transcribe` | Direct audio transcription |

## 🎨 Mobile App Features

### Main Screen
- Device connection status
- Real-time audio streaming indicator
- Recording controls (Start/Stop)
- Battery level display
- Button event notifications

### Recordings
- List of saved recordings
- Play, Share, Delete actions
- Transcription status
- AI analysis results

### Settings
- Backend configuration
- AI model selection
- Audio quality settings
- Storage preferences

### Firmware Updates
- Current firmware version
- Available updates
- OTA update progress
- Manual firmware selection

## 🔄 Integration Architecture

### Audio Pipeline
```
Omi Device → BLE → Flutter App → WebSocket → Backend → Whisper → Text
                                                      ↓
                                               Ollama → Analysis → Storage
```

### Data Flow
1. **Audio Capture**: Omi device streams audio via BLE to Flutter app
2. **WebSocket Streaming**: App sends audio chunks to backend via WebSocket
3. **Transcription**: Backend uses Faster Whisper to convert speech to text
4. **Analysis**: Ollama processes transcript for summary, action items, memories
5. **Storage**: Results saved to PostgreSQL, audio to MinIO, vectors to Qdrant
6. **Retrieval**: App can query conversations, search memories, chat with history

## 🛡️ Security

- **API Key Authentication**: All API endpoints require valid API key
- **WebSocket Authentication**: API key required in headers
- **Local Network**: Designed for local network deployment
- **No Cloud Dependencies**: All processing happens on your infrastructure

## 📊 Performance

### On RX 7900 XTX (24GB VRAM)

| Task | Model | Time | VRAM Usage |
|------|-------|------|------------|
| Transcribe 1 min | Large-v3 | ~10-12s | ~3GB |
| Generate 500 tokens | qwen2.5:14b | ~6-7s | ~10GB |
| Generate 500 tokens | llama3.1:8b | ~4-5s | ~5GB |
| Embedding | nomic-embed-text | ~1-2s | ~300MB |

### Recommended Model Combinations

| Whisper | LLM | Total VRAM | Quality | Speed |
|--------|-----|-----------|---------|-------|
| Large-v3 | qwen2.5:32b | ~23GB | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| Large-v3 | qwen2.5:14b | ~13GB | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| Medium | qwen2.5:14b | ~11GB | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| Medium | llama3.1:8b | ~6.5GB | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](docs/developer/CONTRIBUTING.md) for details.

## 📜 License

This project inherits licenses from the original Omi project and associated components. See [LICENSE](LICENSE) for details.

## 🙏 Acknowledgments

- [Based Hardware](https://github.com/BasedHardware) - Original Omi project
- [Omi Community](https://omi.me) - Community support and contributions
- [Flutter Team](https://flutter.dev) - Cross-platform framework
- [FastAPI](https://fastapi.tiangolo.com) - Backend framework
- [Ollama](https://ollama.com) - Local LLM inference
- [Faster Whisper](https://github.com/SYSTRAN/faster-whisper) - Speech-to-text

---

**Omi Omni** - Your Omi, Your Data, Your Control
