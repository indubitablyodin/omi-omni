#!/usr/bin/env python3
"""
Faster Whisper Server for Omi Omni
AMD ROCm compatible
"""

import os
import io
import logging
from fastapi import FastAPI, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from faster_whisper import WhisperModel
import uvicorn

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Omi Omni Whisper Server")

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Load model
MODEL_PATH = os.getenv("WHISPER__MODEL", "Systran/faster-whisper-large-v3")
DEVICE = os.getenv("WHISPER__DEVICE", "auto")
COMPUTE_TYPE = os.getenv("WHISPER__COMPUTE_TYPE", "float16")

logger.info(f"Loading Whisper model: {MODEL_PATH}")
logger.info(f"Device: {DEVICE}, Compute type: {COMPUTE_TYPE}")

try:
    model = WhisperModel(
        MODEL_PATH,
        device=DEVICE,
        compute_type=COMPUTE_TYPE,
        cpu_threads=4,
        num_workers=1,
    )
    logger.info("Model loaded successfully")
except Exception as e:
    logger.error(f"Failed to load model: {e}")
    raise


@app.get("/health")
async def health():
    """Health check endpoint"""
    return {"status": "healthy", "model": MODEL_PATH, "device": DEVICE}


@app.post("/transcribe")
async def transcribe(audio: UploadFile):
    """Transcribe audio file"""
    try:
        # Read audio file
        audio_bytes = await audio.read()
        
        # Transcribe
        segments, info = model.transcribe(
            io.BytesIO(audio_bytes),
            beam_size=5,
            log_prob_threshold=-1.0,
            no_speech_threshold=0.6,
            condition_on_previous_text=False,
            temperature=0.0,
        )
        
        # Combine segments
        text = "".join(segment.text for segment in segments)
        
        return {
            "text": text,
            "language": info.language,
            "language_probability": info.language_probability,
            "duration": info.duration,
        }
    except Exception as e:
        logger.error(f"Transcription error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/transcribe-stream")
async def transcribe_stream(audio: UploadFile):
    """Streaming transcription with word-level timestamps"""
    try:
        audio_bytes = await audio.read()
        
        segments, info = model.transcribe(
            io.BytesIO(audio_bytes),
            beam_size=5,
            word_timestamps=True,
            log_prob_threshold=-1.0,
            no_speech_threshold=0.6,
        )
        
        # Format with word timestamps
        words = []
        for segment in segments:
            for word in segment.words:
                words.append({
                    "word": word.word,
                    "start": word.start,
                    "end": word.end,
                })
        
        text = "".join(segment.text for segment in segments)
        
        return {
            "text": text,
            "words": words,
            "language": info.language,
            "language_probability": info.language_probability,
            "duration": info.duration,
        }
    except Exception as e:
        logger.error(f"Stream transcription error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8000,
        log_level="info",
    )
