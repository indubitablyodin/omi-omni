# Open Issues and Fixes

This document tracks all open GitHub issues and their proposed solutions.

## 🔴 Critical Bugs (Priority: High)

### Issue #1: Fix WebSocket URL scheme for backend audio streaming
**Status:** ✅ FIXED in commit 2a43b94

**Problem:** The app was using `apiBaseUrl.replaceFirst('http', 'ws')` which incorrectly transforms `https://` to `wss://` (becomes `wsss://`).

**Fix:** Updated `app/lib/config/app_config.dart` to properly handle both http:// and https:// schemes:
```dart
String get audioWebSocketUrl {
  if (apiBaseUrl.startsWith('https://')) {
    return apiBaseUrl.replaceFirst('https://', 'wss://');
  } else if (apiBaseUrl.startsWith('http://')) {
    return apiBaseUrl.replaceFirst('http://', 'ws://');
  }
  return apiBaseUrl.startsWith('ws://') || apiBaseUrl.startsWith('wss://')
      ? apiBaseUrl
      : 'ws://$apiBaseUrl';
}
```

---

### Issue #2: Fix FastAPI WebSocket receive loop to handle binary audio frames
**Status:** ⚠️ NEEDS FIX

**Problem:** The WebSocket handler in `backend/main.py` doesn't properly handle FastAPI's `WebSocketMessage` objects. It checks `isinstance(message, bytes)` but FastAPI wraps messages.

**Current Code (line ~172):**
```python
message = await websocket.receive()
if isinstance(message, bytes):
    audio_buffer.extend(message)
```

**Fix:** FastAPI's `receive()` returns a dict with `"type"`, `"bytes"`, or `"text"` keys:
```python
message = await websocket.receive()
if message.get("type") == "websocket.receive":
    if "bytes" in message:
        audio_buffer.extend(message["bytes"])
    elif "text" in message:
        # Handle text message
        pass
```

**File:** `backend/main.py`, function `audio_websocket()`

---

### Issue #3: Align Whisper client endpoint with bundled Whisper server
**Status:** ⚠️ NEEDS FIX

**Problem:** The backend's Whisper client expects a specific endpoint that doesn't match the bundled whisper-server.py.

**Current:** Backend tries to call Whisper service at `/transcribe` endpoint
**Bundled Server:** whisper-server.py has `/transcribe` and `/transcribe-stream` endpoints

**Fix:** Ensure the backend's `WhisperService` class uses the correct endpoint. Check `backend/services.py`:
```python
class WhisperService:
    async def transcribe(self, audio_bytes: bytes) -> str:
        # Should call: http://whisper:8000/transcribe
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"http://{self.host}:{self.port}/transcribe",
                files={"audio": ("audio.wav", audio_bytes)},
            )
            return response.json()["text"]
```

**File:** `backend/services.py`

---

### Issue #4: Fix missing SQLAlchemy imports in database models
**Status:** ⚠️ NEEDS FIX

**Problem:** The `database.py` file has corrupted placeholders and missing imports.

**Issues Found:**
1. Line 20: `DATABASE_URL` has `********` instead of user/password
2. Line 169: `async def get_db() -> AsyncGenerator[AsyncSession, None]:` has corrupted yield statement
3. Missing `Float` import for `confidence` field in ConversationSegment

**Fix:**
1. Fix DATABASE_URL:
```python
DATABASE_URL = f"postgresql+asyncpg://{settings.postgres_user}:{settings.postgres_password}@{settings.postgres_host}:{settings.postgres_port}/{settings.postgres_db}"
```

2. Add Float import:
```python
from sqlalchemy import Column, Integer, String, Text, DateTime, JSON, ForeignKey, Float, func
```

3. Fix get_db function:
```python
async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """Dependency to get database session."""
    async with async_session() as session:
        try:
            yield session
            await session.commit()
        except Exception as e:
            await session.rollback()
            logger.error(f"Database error: {e}")
            raise
        finally:
            await session.close()
```

**File:** `backend/database.py`

---

### Issue #5: Fix Dart final field reassignment in BackendProvider
**Status:** ⚠️ NEEDS FIX

**Problem:** Dart doesn't allow reassignment of `final` fields, but the BackendProvider tries to reassign them.

**Current Code:** Check `app/lib/providers/backend_provider.dart` for lines like:
```dart
final WebSocket? _audioWebSocket;
...
_audioWebSocket = await _apiClient.connectAudioWebSocket(); // ERROR: Can't assign to final
```

**Fix:** Remove `final` keyword from fields that need reassignment:
```dart
WebSocket? _audioWebSocket;  // Remove final
bool _isConnected = false;    // Remove final
```

**File:** `app/lib/providers/backend_provider.dart`

---

## 🟡 Enhancements (Priority: Medium)

### Issue #6: Wire CaptureProvider to BackendProvider for actual backend audio streaming
**Status:** ⚠️ NEEDS IMPLEMENTATION

**Problem:** The CaptureProvider collects audio but doesn't send it to the BackendProvider for streaming to the backend.

**Fix:** In `app/lib/providers/capture_provider.dart`, add logic to send audio chunks to the backend:
```dart
// In CaptureProvider._onAudioAvailable():
if (backendProvider.isConnected) {
  await backendProvider.sendAudioChunk(audioBytes);
}
```

**Files:**
- `app/lib/providers/capture_provider.dart`
- `app/lib/providers/backend_provider.dart` (add `sendAudioChunk` method)

---

### Issue #7: Make local-only privacy mode the safe default
**Status:** ⚠️ NEEDS IMPLEMENTATION

**Problem:** Cloud transcription should be disabled by default for privacy.

**Fix:** In `app/lib/config/app_config.dart`:
```dart
// Change default to false
bool enableCloudTranscription = false;
bool enableAiProcessing = true;  // Local only
```

**File:** `app/lib/config/app_config.dart`

---

### Issue #8: Clarify privacy model documentation
**Status:** ⚠️ NEEDS DOCUMENTATION

**Problem:** Need to document that local-first/self-hosted is NOT end-to-end encrypted.

**Fix:** Add to `README.md`:
```markdown
## 🔒 Privacy Model

**Important:** Omi Omni is **local-first and self-hosted**, but this does NOT mean end-to-end encrypted:

- ✅ Audio is processed on your own server (not in the cloud)
- ✅ Data stays in your database (PostgreSQL, Qdrant, etc.)
- ✅ No third-party cloud services by default
- ❌ Data is NOT encrypted at rest (plaintext in your database)
- ❌ Data is NOT encrypted in transit between app and backend (HTTP, not HTTPS by default)

**To enable encryption:**
1. Use HTTPS for backend (configure reverse proxy with SSL)
2. Enable database encryption (PostgreSQL TDE)
3. Use encrypted volumes for Docker
```

**File:** `README.md` (add Privacy section)

---

## 🟢 Already Fixed

### Issue #9: Add lightweight profile for MacBook Air / low-RAM deployments
**Status:** ✅ FIXED in commit 2a43b94
- Added `docker-compose-mac.yml`
- Added `.env.mac` template
- Added `make start-mac` command

### Issue #10: Add model tier configuration for STT and LLM based on available RAM
**Status:** ✅ FIXED in commit 2a43b94
- Added `MODEL_TIER` environment variable
- Configured lightweight models for Mac

### Issue #11: Support Apple Silicon optimized transcription backend
**Status:** ✅ FIXED in commit 2a43b94
- All Docker images support ARM64
- Ollama uses Metal acceleration automatically

### Issue #16: Document MacBook Air M4 setup guide
**Status:** ✅ FIXED in commit 2a43b94
- Added `docs/user/macbook-air-m4.md`

---

## 🟡 Additional Enhancements (Priority: Low)

### Issue #12: Add resource limits and health checks for Docker services
**Status:** ⚠️ PARTIALLY FIXED

**Current:** Health checks are present in docker-compose files
**Missing:** Resource limits (CPU, memory) for each service

**Fix:** Add to each service in docker-compose files:
```yaml
deploy:
  resources:
    limits:
      cpus: '1.0'
      memory: 2G
    reservations:
      cpus: '0.5'
      memory: 512M
```

**Files:** All docker-compose files

---

### Issue #13: Implement sequential/background processing mode
**Status:** ⚠️ NEEDS IMPLEMENTATION

**Problem:** Processing audio in real-time can cause peak memory usage.

**Fix:** Add queue system (Redis) for background processing:
```python
# In backend/main.py
from services import TaskQueue

@app.websocket("/ws/audio")
async def audio_websocket(...):
    # Instead of processing immediately:
    await task_queue.enqueue("transcribe", {
        "conversation_id": conversation_id,
        "audio_bytes": base64.b64encode(audio_buffer).decode(),
    })
    audio_buffer = bytearray()
```

**Files:**
- `backend/main.py`
- `backend/services.py` (add TaskQueue class)

---

### Issue #14: Add audio chunking and streaming transcription
**Status:** ⚠️ NEEDS IMPLEMENTATION

**Problem:** Large audio buffers can cause memory issues.

**Fix:** Process audio in chunks:
```python
# In backend/main.py audio_websocket():
CHUNK_SIZE = 1024 * 1024  # 1MB chunks

if len(audio_buffer) >= CHUNK_SIZE:
    chunk = audio_buffer[:CHUNK_SIZE]
    audio_buffer = audio_buffer[CHUNK_SIZE:]
    
    # Process chunk immediately
    await process_audio_chunk(chunk, conversation_id, websocket)
```

**File:** `backend/main.py`

---

### Issue #15: Add local performance benchmark script
**Status:** ⚠️ NEEDS IMPLEMENTATION

**Fix:** Create `scripts/benchmark.sh`:
```bash
#!/bin/bash
# Benchmark transcription and LLM performance

echo "=== Omi Omni Performance Benchmark ==="
echo ""

# Test Whisper
echo "Testing Whisper transcription..."
time curl -s -F "audio=@test-audio.wav" http://localhost:8001/transcribe > /dev/null

# Test LLM
echo "Testing LLM inference..."
time curl -s -X POST http://localhost:11434/api/generate -d '{"model":"qwen2.5:0.5b","prompt":"Test"}' > /dev/null

echo "Benchmark complete"
```

**File:** `scripts/benchmark.sh`

---

### Issue #17: Add configuration flag to disable non-essential indexing
**Status:** ⚠️ NEEDS IMPLEMENTATION

**Fix:** Add environment variable:
```bash
DISABLE_MEMORY_INDEXING=false  # Set to true to disable Qdrant/Meilisearch
```

In `backend/main.py`:
```python
if not settings.disable_memory_indexing:
    # Index conversation in Qdrant
    await vector_service.index_memory(memory)
```

**Files:**
- `.env.example` (add variable)
- `backend/config.py` (add setting)
- `backend/main.py` (check setting before indexing)

---

### Issue #18: Add graceful fallback when LLM or STT model is unavailable
**Status:** ⚠️ NEEDS IMPLEMENTATION

**Fix:** Add fallback logic in services:
```python
# In backend/services.py
class LLMService:
    async def generate(self, prompt: str) -> str:
        try:
            # Try primary LLM
            return await self._call_ollama(prompt)
        except Exception as e:
            logger.warning(f"Primary LLM failed: {e}")
            
            # Fallback to smaller model
            try:
                return await self._call_ollama(prompt, model="phi3:3.8b-mini")
            except Exception as e:
                logger.error(f"All LLM attempts failed: {e}")
                return "Sorry, I'm having trouble processing your request."
```

**File:** `backend/services.py`

---

## 📋 Summary

| Issue | Status | Priority | File |
|-------|--------|----------|------|
| #1 | ✅ Fixed | High | app/lib/config/app_config.dart |
| #2 | ⚠️ Needs Fix | High | backend/main.py |
| #3 | ⚠️ Needs Fix | High | backend/services.py |
| #4 | ⚠️ Needs Fix | High | backend/database.py |
| #5 | ⚠️ Needs Fix | High | app/lib/providers/backend_provider.dart |
| #6 | ⚠️ Needs Fix | Medium | app/lib/providers/capture_provider.dart |
| #7 | ⚠️ Needs Fix | Medium | app/lib/config/app_config.dart |
| #8 | ⚠️ Needs Fix | Medium | README.md |
| #9 | ✅ Fixed | Medium | docker-compose-mac.yml, .env.mac |
| #10 | ✅ Fixed | Medium | docker-compose-mac.yml |
| #11 | ✅ Fixed | Medium | docker-compose-mac.yml |
| #12 | ⚠️ Partial | Low | docker-compose-*.yml |
| #13 | ⚠️ Needs Fix | Low | backend/main.py, backend/services.py |
| #14 | ⚠️ Needs Fix | Low | backend/main.py |
| #15 | ⚠️ Needs Fix | Low | scripts/benchmark.sh |
| #16 | ✅ Fixed | Low | docs/user/macbook-air-m4.md |
| #17 | ⚠️ Needs Fix | Low | backend/config.py, backend/main.py |
| #18 | ⚠️ Needs Fix | Low | backend/services.py |

## 🚀 Next Steps

1. **Fix Critical Bugs (#2-#5)** - These prevent the system from working
2. **Implement Enhancements (#6-#8)** - Improve functionality
3. **Add Nice-to-Haves (#12-#18)** - Polish the experience

Run `scripts/fix-issues.sh` to apply automated fixes.
