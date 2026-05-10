"""
Omi Omni Backend
================
FastAPI backend for the Omi Omni application.
Handles audio ingestion, transcription, LLM processing, and memory storage.
"""

import json
import uuid
import logging
from datetime import datetime
from contextlib import asynccontextmanager
from typing import Optional, List, Dict, Any

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException, Depends, Header, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from sqlalchemy import text, select, insert, update, delete
from sqlalchemy.ext.asyncio import AsyncSession

from config import get_settings, reload_settings
from database import get_db, Base, engine
from services import WhisperService, LLMService, StorageService, VectorService, SearchService, get_redis, ServiceRegistry

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)

settings = get_settings()


# =============================================================================
# Lifespan: initialize services on startup
# =============================================================================
@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Starting Omi Omni backend...")
    
    # Initialize service registry
    app.state.services = ServiceRegistry()
    
    # Initialize database
    async with engine.begin() as conn:
        # Create all tables if they don't exist
        await conn.run_sync(Base.metadata.create_all)
    
    logger.info("All services initialized.")
    yield
    
    # Cleanup
    await app.state.services.close()
    logger.info("Backend shut down.")


app = FastAPI(
    title="Omi Omni Backend",
    version="0.1.0",
    description="Self-hosted backend for Omi AI wearable with full local capabilities",
    lifespan=lifespan,
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# =============================================================================
# Auth Dependency
# =============================================================================
async def verify_api_key(authorization: Optional[str] = Header(None)):
    """Verify API key from Authorization header."""
    if not authorization:
        raise HTTPException(status_code=401, detail="Missing API key")
    
    key = authorization.replace("Bearer ", "")
    if key != settings.api_key:
        raise HTTPException(status_code=401, detail="Invalid API key")
    
    return key


# =============================================================================
# Health Check Endpoint
# =============================================================================
@app.get("/health")
async def health(db: AsyncSession = Depends(get_db)):
    """Health check endpoint with service status."""
    checks = {}
    
    # Database check
    try:
        await db.execute(text("SELECT 1"))
        checks["postgres"] = "ok"
    except Exception as e:
        checks["postgres"] = f"error: {e}"
    
    # Service checks
    service_checks = await app.state.services.health_check_all()
    checks.update(service_checks)
    
    all_ok = all(v == "ok" or v is True for v in checks.values())
    
    return JSONResponse(
        content={
            "status": "healthy" if all_ok else "degraded",
            "version": "0.1.0",
            "services": checks,
            "timestamp": datetime.utcnow().isoformat(),
        }
    )


# =============================================================================
# WebSocket: Audio Streaming & Transcription
# =============================================================================
class ConnectionManager:
    """Manage WebSocket connections."""
    
    def __init__(self):
        self.active_connections: List[WebSocket] = []
    
    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)
    
    def disconnect(self, websocket: WebSocket):
        self.active_connections.remove(websocket)
    
    async def broadcast(self, message: str):
        for connection in self.active_connections:
            await connection.send_text(message)


manager = ConnectionManager()


@app.websocket("/ws/audio")
async def audio_websocket(
    websocket: WebSocket,
    db: AsyncSession = Depends(get_db),
    api_key: str = Depends(verify_api_key)
):
    """
    WebSocket endpoint for real-time audio streaming.
    
    The Omi app sends audio chunks; we accumulate, transcribe, and respond.
    
    Message Types:
    - Binary: Raw audio bytes (accumulated until connection closes)
    - JSON: Control messages (start, stop, config)
    """
    await manager.connect(websocket)
    logger.info(f"Audio WebSocket connected (API key: {api_key[:8]}...)")
    
    audio_buffer = bytearray()
    conversation_id = str(uuid.uuid4())
    started_at = datetime.utcnow()
    is_streaming = False
    
    try:
        while True:
            # Receive message (can be binary or text)
            try:
                message = await websocket.receive()
            except WebSocketDisconnect:
                break
            
            # Handle binary audio data
            if isinstance(message, bytes):
                audio_buffer.extend(message)
                is_streaming = True
                
                # Send keepalive acknowledgment every few chunks
                if len(audio_buffer) % (settings.max_audio_chunk_size * 10) < settings.max_audio_chunk_size:
                    await websocket.send_json({
                        "type": "ack",
                        "bytes_received": len(audio_buffer),
                        "conversation_id": conversation_id,
                    })
                continue
            
            # Handle text/JSON messages
            if isinstance(message, str):
                try:
                    data = json.loads(message)
                    message_type = data.get("type")
                    
                    if message_type == "start":
                        # Start new conversation
                        conversation_id = str(uuid.uuid4())
                        audio_buffer = bytearray()
                        started_at = datetime.utcnow()
                        is_streaming = True
                        
                        await websocket.send_json({
                            "type": "started",
                            "conversation_id": conversation_id,
                        })
                        logger.info(f"Started new conversation: {conversation_id}")
                    
                    elif message_type == "stop":
                        # Stop current conversation and process
                        is_streaming = False
                        if len(audio_buffer) > 1000:  # Minimum audio length
                            await process_conversation(
                                conversation_id=conversation_id,
                                audio_bytes=bytes(audio_buffer),
                                started_at=started_at,
                                db=db,
                                websocket=websocket,
                            )
                        audio_buffer = bytearray()
                        
                    elif message_type == "config":
                        # Update configuration
                        logger.info(f"Received config: {data}")
                        
                    elif message_type == "ping":
                        await websocket.send_json({"type": "pong"})
                    
                except json.JSONDecodeError:
                    logger.warning(f"Received non-JSON text message: {message[:100]}")
                    continue
    
    except Exception as e:
        logger.error(f"WebSocket error: {e}")
    
    finally:
        manager.disconnect(websocket)
        logger.info(f"Audio WebSocket disconnected. Buffer size: {len(audio_buffer)} bytes")
        
        # Process any remaining audio
        if is_streaming and len(audio_buffer) > 1000:
            try:
                await process_conversation(
                    conversation_id=conversation_id,
                    audio_bytes=bytes(audio_buffer),
                    started_at=started_at,
                    db=db,
                    websocket=None,  # No websocket to send results to
                )
            except Exception as e:
                logger.error(f"Error processing final audio: {e}")


async def process_conversation(
    conversation_id: str,
    audio_bytes: bytes,
    started_at: datetime,
    db: AsyncSession,
    websocket: Optional[WebSocket] = None,
):
    """Full pipeline: store audio → transcribe → summarize → extract memories."""
    logger.info(f"Processing conversation {conversation_id} ({len(audio_bytes)} bytes)")
    
    try:
        # 1. Store audio in MinIO
        audio_path = f"{conversation_id}.opus"
        app.state.services.storage.upload_audio(audio_path, audio_bytes)
        logger.info(f"Audio stored: {audio_path}")
        
        # Send progress update
        if websocket:
            await websocket.send_json({
                "type": "progress",
                "step": "storing",
                "conversation_id": conversation_id,
            })
        
        # 2. Transcribe with Whisper
        if websocket:
            await websocket.send_json({
                "type": "progress",
                "step": "transcribing",
                "conversation_id": conversation_id,
            })
        
        transcript_result = await app.state.services.whisper.transcribe(audio_bytes)
        transcript_text = transcript_result.get("text", "")
        segments = transcript_result.get("segments", [])
        logger.info(f"Transcription complete: {len(transcript_text)} chars, {len(segments)} segments")
        
        if not transcript_text.strip():
            logger.info("Empty transcript, skipping")
            if websocket:
                await websocket.send_json({
                    "type": "error",
                    "message": "Empty transcript",
                    "conversation_id": conversation_id,
                })
            return
        
        # 3. Summarize with LLM
        if websocket:
            await websocket.send_json({
                "type": "progress",
                "step": "analyzing",
                "conversation_id": conversation_id,
            })
        
        analysis = await app.state.services.llm.summarize_conversation(transcript_text)
        logger.info(f"Analysis complete: {analysis.get('summary', '')[:100]}...")
        
        # 4. Store conversation in PostgreSQL
        finished_at = datetime.utcnow()
        
        await db.execute(
            text("""
                INSERT INTO conversations (id, title, status, started_at, finished_at,
                                       transcript, summary, action_items, key_topics, audio_path)
                VALUES (:id, :title, 'completed', :started_at, :finished_at,
                        :transcript, :summary, :action_items, :key_topics, :audio_path)
            """),
            {
                "id": conversation_id,
                "title": analysis.get("summary", "Untitled")[:100],
                "started_at": started_at,
                "finished_at": finished_at,
                "transcript": transcript_text,
                "summary": analysis.get("summary", ""),
                "action_items": json.dumps(analysis.get("action_items", [])),
                "key_topics": json.dumps(analysis.get("key_topics", [])),
                "audio_path": audio_path,
            },
        )
        await db.commit()
        
        # 5. Store segments
        for i, seg in enumerate(segments):
            await db.execute(
                text("""
                    INSERT INTO conversation_segments (conversation_id, text, start_time, end_time,
                                                    confidence, segment_index)
                    VALUES (:conv_id, :text, :start, :end, :confidence, :idx)
                """),
                {
                    "conv_id": conversation_id,
                    "text": seg.get("text", ""),
                    "start": seg.get("start", 0),
                    "end": seg.get("end", 0),
                    "confidence": seg.get("avg_logprob", 0),
                    "idx": i,
                },
            )
        await db.commit()
        
        # 6. Extract and store memories in Qdrant
        memories = analysis.get("memories", [])
        for memory_text in memories:
            memory_id = str(uuid.uuid4())
            try:
                embedding = await app.state.services.llm.embed(memory_text)
                app.state.services.vectors.upsert(
                    point_id=memory_id,
                    vector=embedding,
                    payload={
                        "text": memory_text,
                        "conversation_id": conversation_id,
                        "created_at": datetime.utcnow().isoformat(),
                    },
                )
                
                await db.execute(
                    text("""
                        INSERT INTO memories (id, conversation_id, content, embedding_id, category)
                        VALUES (:id, :conv_id, :content, :embedding_id, 'conversation')
                    """),
                    {
                        "id": memory_id,
                        "conv_id": conversation_id,
                        "content": memory_text,
                        "embedding_id": memory_id,
                    },
                )
            except Exception as e:
                logger.error(f"Error storing memory: {e}")
        await db.commit()
        
        # 7. Add to Meilisearch
        try:
            await app.state.services.search.add_document(
                "conversations",
                {
                    "id": conversation_id,
                    "title": analysis.get("summary", "Untitled")[:100],
                    "summary": analysis.get("summary", ""),
                    "transcript": transcript_text,
                    "started_at": started_at.isoformat(),
                    "finished_at": finished_at.isoformat(),
                }
            )
        except Exception as e:
            logger.warning(f"Failed to index conversation in Meilisearch: {e}")
        
        logger.info(f"Conversation {conversation_id} fully processed. {len(memories)} memories stored.")
        
        # Send completion notification
        if websocket:
            await websocket.send_json({
                "type": "complete",
                "conversation_id": conversation_id,
                "summary": analysis.get("summary", ""),
                "action_items": analysis.get("action_items", []),
                "key_topics": analysis.get("key_topics", []),
                "memories_count": len(memories),
                "audio_path": audio_path,
                "started_at": started_at.isoformat(),
                "finished_at": finished_at.isoformat(),
            })
    
    except Exception as e:
        logger.error(f"Error processing conversation {conversation_id}: {e}")
        if websocket:
            await websocket.send_json({
                "type": "error",
                "message": str(e),
                "conversation_id": conversation_id,
            })


# =============================================================================
# REST API: Conversations
# =============================================================================
class ConversationResponse(BaseModel):
    id: str
    title: Optional[str] = None
    summary: Optional[str] = None
    transcript: Optional[str] = None
    action_items: List[str] = []
    key_topics: List[str] = []
    started_at: Optional[str] = None
    finished_at: Optional[str] = None
    audio_path: Optional[str] = None


@app.get("/v1/conversations", response_model=List[ConversationResponse])
async def list_conversations(
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    _: str = Depends(verify_api_key),
    db: AsyncSession = Depends(get_db),
):
    """List all conversations."""
    result = await db.execute(
        text("""
            SELECT id, title, summary, action_items, key_topics, started_at, finished_at, audio_path
            FROM conversations
            WHERE status = 'completed'
            ORDER BY created_at DESC
            LIMIT :limit OFFSET :offset
        """),
        {"limit": limit, "offset": offset},
    )
    rows = result.fetchall()
    
    return [
        {
            "id": str(r.id),
            "title": r.title,
            "summary": r.summary,
            "action_items": r.action_items or [],
            "key_topics": r.key_topics or [],
            "started_at": r.started_at.isoformat() if r.started_at else None,
            "finished_at": r.finished_at.isoformat() if r.finished_at else None,
            "audio_path": r.audio_path,
        }
        for r in rows
    ]


@app.get("/v1/conversations/{conversation_id}", response_model=ConversationResponse)
async def get_conversation(
    conversation_id: str,
    _: str = Depends(verify_api_key),
    db: AsyncSession = Depends(get_db),
):
    """Get conversation details."""
    result = await db.execute(
        text("SELECT * FROM conversations WHERE id = :id"),
        {"id": conversation_id},
    )
    row = result.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Conversation not found")
    
    return {
        "id": str(row.id),
        "title": row.title,
        "summary": row.summary,
        "transcript": row.transcript,
        "action_items": row.action_items or [],
        "key_topics": row.key_topics or [],
        "started_at": row.started_at.isoformat() if row.started_at else None,
        "finished_at": row.finished_at.isoformat() if row.finished_at else None,
        "audio_path": row.audio_path,
    }


@app.delete("/v1/conversations/{conversation_id}")
async def delete_conversation(
    conversation_id: str,
    _: str = Depends(verify_api_key),
    db: AsyncSession = Depends(get_db),
):
    """Delete a conversation and its associated data."""
    # Get conversation first
    result = await db.execute(
        text("SELECT audio_path FROM conversations WHERE id = :id"),
        {"id": conversation_id},
    )
    row = result.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Conversation not found")
    
    audio_path = row.audio_path
    
    # Delete from all related tables
    await db.execute(
        text("DELETE FROM conversation_segments WHERE conversation_id = :id"),
        {"id": conversation_id},
    )
    await db.execute(
        text("DELETE FROM memories WHERE conversation_id = :id"),
        {"id": conversation_id},
    )
    await db.execute(
        text("DELETE FROM conversations WHERE id = :id"),
        {"id": conversation_id},
    )
    await db.commit()
    
    # Delete audio file from MinIO
    if audio_path:
        try:
            app.state.services.storage.delete_audio(audio_path.split("/")[-1])
        except Exception as e:
            logger.warning(f"Failed to delete audio file {audio_path}: {e}")
    
    # Delete from Qdrant (memories associated with this conversation)
    try:
        # This would require tracking which memory IDs belong to which conversation
        # For now, we'll skip this as it's complex to implement
        pass
    except Exception as e:
        logger.warning(f"Failed to delete vectors for conversation {conversation_id}: {e}")
    
    return JSONResponse(
        content={"message": "Conversation deleted successfully"},
        status_code=200,
    )


# =============================================================================
# REST API: Memories
# =============================================================================
class MemoryResponse(BaseModel):
    id: str
    content: str
    conversation_id: Optional[str] = None
    category: Optional[str] = None
    created_at: Optional[str] = None


@app.get("/v1/memories", response_model=List[MemoryResponse])
async def list_memories(
    limit: int = Query(default=50, ge=1, le=100),
    _: str = Depends(verify_api_key),
    db: AsyncSession = Depends(get_db),
):
    """List all memories."""
    result = await db.execute(
        text("SELECT id, content, conversation_id, category, created_at FROM memories ORDER BY created_at DESC LIMIT :limit"),
        {"limit": limit},
    )
    return [
        {
            "id": str(r.id),
            "content": r.content,
            "conversation_id": str(r.conversation_id) if r.conversation_id else None,
            "category": r.category,
            "created_at": r.created_at.isoformat() if r.created_at else None,
        }
        for r in result.fetchall()
    ]


@app.get("/v1/memories/search")
async def search_memories(
    q: str = Query(..., description="Search query"),
    limit: int = Query(default=10, ge=1, le=20),
    _: str = Depends(verify_api_key),
):
    """Semantic search over memories using Qdrant."""
    try:
        # Get embedding for query
        embedding = await app.state.services.llm.embed(q)
        
        # Search Qdrant
        results = app.state.services.vectors.search(embedding, limit=limit)
        
        return [
            {
                "id": r.id,
                "text": r.payload.get("text"),
                "score": r.score,
                "conversation_id": r.payload.get("conversation_id"),
                "created_at": r.payload.get("created_at"),
            }
            for r in results
        ]
    except Exception as e:
        logger.error(f"Memory search failed: {e}")
        raise HTTPException(status_code=500, detail="Memory search failed")


# =============================================================================
# REST API: Chat (query your conversations with LLM)
# =============================================================================
class ChatRequest(BaseModel):
    message: str
    context_limit: Optional[int] = 5


class ChatResponse(BaseModel):
    response: str
    conversation_id: Optional[str] = None


@app.post("/v1/chat", response_model=ChatResponse)
async def chat(
    request: ChatRequest,
    _: str = Depends(verify_api_key),
    db: AsyncSession = Depends(get_db),
):
    """Chat with your conversation history using semantic search + LLM."""
    try:
        # Find relevant memories
        embedding = await app.state.services.llm.embed(request.message)
        memory_results = app.state.services.vectors.search(embedding, limit=request.context_limit or 5)
        context = "\n".join([r.payload.get("text", "") for r in memory_results])
        
        # Find recent conversations
        result = await db.execute(
            text("SELECT summary FROM conversations WHERE status = 'completed' ORDER BY created_at DESC LIMIT 5")
        )
        recent_summaries = "\n".join([r.summary for r in result.fetchall() if r.summary])
        
        messages = [
            {
                "role": "system",
                "content": (
                    "You are a helpful assistant with access to the user's conversation history. "
                    "Use the following context to answer their question.\n\n"
                    f"Relevant memories:\n{context}\n\n"
                    f"Recent conversation summaries:\n{recent_summaries}"
                ),
            },
            {"role": "user", "content": request.message},
        ]
        
        response = await app.state.services.llm.chat(messages)
        
        return {"response": response}
    except Exception as e:
        logger.error(f"Chat failed: {e}")
        raise HTTPException(status_code=500, detail="Chat failed")


# =============================================================================
# REST API: Audio File Operations
# =============================================================================
@app.get("/v1/audio/{file_name}")
async def get_audio_file(
    file_name: str,
    _: str = Depends(verify_api_key),
):
    """Download an audio file."""
    try:
        audio_data = app.state.services.storage.get_audio(file_name)
        return JSONResponse(content={"audio": audio_data.hex()})
    except Exception as e:
        raise HTTPException(status_code=404, detail="Audio file not found")


@app.get("/v1/audio")
async def list_audio_files(
    _: str = Depends(verify_api_key),
):
    """List all audio files."""
    try:
        files = app.state.services.storage.list_audio_files()
        return {"files": files}
    except Exception as e:
        raise HTTPException(status_code=500, detail="Failed to list audio files")


# =============================================================================
# REST API: Statistics
# =============================================================================
@app.get("/v1/stats")
async def get_stats(
    _: str = Depends(verify_api_key),
    db: AsyncSession = Depends(get_db),
):
    """Get usage statistics."""
    try:
        # Conversation count
        conv_result = await db.execute(text("SELECT COUNT(*) FROM conversations"))
        conv_count = conv_result.scalar()
        
        # Memory count
        mem_result = await db.execute(text("SELECT COUNT(*) FROM memories"))
        mem_count = mem_result.scalar()
        
        # Storage usage
        audio_files = app.state.services.storage.list_audio_files()
        total_audio_size = sum(
            len(app.state.services.storage.get_audio(f)) 
            for f in audio_files[:100]  # Limit to first 100 for performance
        )
        
        # Qdrant stats
        try:
            collection_info = app.state.services.vectors.client.get_collection(
                app.state.services.vectors.collection
            )
            vector_count = collection_info.points_count
        except:
            vector_count = 0
        
        return {
            "conversations": int(conv_count) if conv_count else 0,
            "memories": int(mem_count) if mem_count else 0,
            "audio_files": len(audio_files),
            "audio_storage_size": total_audio_size,
            "vectors": vector_count,
        }
    except Exception as e:
        logger.error(f"Stats failed: {e}")
        return {
            "conversations": 0,
            "memories": 0,
            "audio_files": 0,
            "audio_storage_size": 0,
            "vectors": 0,
        }


# =============================================================================
# REST API: Configuration
# =============================================================================
@app.get("/v1/config")
async def get_config(
    _: str = Depends(verify_api_key),
):
    """Get current configuration."""
    return {
        "whisper_model": settings.whisper_model,
        "ollama_model": settings.ollama_model,
        "max_conversation_length": settings.max_conversation_length,
    }


@app.post("/v1/config/reload")
async def reload_config(
    _: str = Depends(verify_api_key),
):
    """Reload configuration from .env file."""
    try:
        reload_settings()
        return {"message": "Configuration reloaded successfully"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to reload config: {e}")


# =============================================================================
# Error Handlers
# =============================================================================
@app.exception_handler(HTTPException)
async def http_exception_handler(request, exc):
    logger.error(f"HTTP Error: {exc.status_code} - {exc.detail}")
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": exc.detail},
    )


@app.exception_handler(Exception)
async def generic_exception_handler(request, exc):
    logger.error(f"Unexpected error: {exc}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={"error": "Internal server error"},
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=settings.backend_port,
        reload=settings.debug,
        log_level="info",
    )
