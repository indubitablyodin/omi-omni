"""
Omi Omni Service Clients
==========================
Service clients for all backend dependencies.
Each client wraps the connection to its respective service.
"""

import io
import httpx
import logging
from typing import Optional, List, Dict, Any
from minio import Minio
from minio.error import S3Error
from qdrant_client import QdrantClient
from qdrant_client.models import Distance, VectorParams, PointStruct, Filter, MustCondition, MatchValue
from redis.asyncio import Redis
from openai import AsyncOpenAI
from config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()


# =============================================================================
# Whisper (Speech-to-Text)
# =============================================================================
class WhisperService:
    """Faster Whisper server — OpenAI-compatible API."""
    
    def __init__(self):
        self.base_url = settings.whisper_url
        self.model = settings.whisper_model
        self.compute_type = settings.whisper_compute_type
        self.timeout = settings.transcription_timeout
        
    async def transcribe(self, audio_bytes: bytes, language: Optional[str] = None) -> str:
        """Transcribe audio bytes. Returns OpenAI-compatible response."""
        try:
            async with httpx.AsyncClient(timeout=120.0) as client:
                response = await client.post(
                    f"http://{settings.whisper_host}:{settings.whisper_port}/v1/audio/transcriptions",
                    files={"file": ("audio.wav", audio_bytes, "audio/wav")},
                    data={"model": settings.whisper_model},
                )
                response.raise_for_status()
                payload = response.json()
                return payload.get("text", "")
        except httpx.TimeoutException as e:
            logger.error(f"Whisper transcription timeout: {e}")
            raise Exception(f"Transcription timeout after {self.timeout} seconds")
        except httpx.HTTPStatusError as e:
            logger.error(f"Whisper HTTP error: {e.response.status_code} - {e.response.text}")
            raise Exception(f"Transcription failed: {e.response.text}")
        except Exception as e:
            logger.error(f"Whisper error: {e}")
            raise Exception(f"Transcription failed: {e}")
    
    async def health_check(self) -> bool:
        """Check if Whisper service is healthy."""
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                response = await client.get(f"{self.base_url}/health")
                return response.status_code == 200
        except Exception as e:
            logger.warning(f"Whisper health check failed: {e}")
            return False


# =============================================================================
# Ollama (LLM — OpenAI-compatible)
# =============================================================================
class LLMService:
    """Ollama via OpenAI-compatible client."""
    
    def __init__(self):
        # Configure Ollama client
        self.client = AsyncOpenAI(
            base_url=f"{settings.ollama_url}/v1",
            api_key="ollama",  # Required but not used by Ollama
            timeout=settings.llm_timeout,
        )
        self.model = settings.ollama_model
        self.embedding_model = "nomic-embed-text"
        
    async def chat(self, messages: List[Dict[str, Any]], temperature: float = 0.7) -> str:
        """Send chat completion request."""
        try:
            response = await self.client.chat.completions.create(
                model=self.model,
                messages=messages,
                temperature=temperature,
            )
            return response.choices[0].message.content
        except Exception as e:
            logger.error(f"LLM chat error: {e}")
            raise Exception(f"LLM generation failed: {e}")
    
    async def summarize_conversation(self, transcript: str) -> Dict[str, Any]:
        """Generate summary, action items, and key topics from a transcript."""
        messages = [
            {
                "role": "system",
                "content": (
                    "You are a conversation analyst. Given a transcript, produce a JSON response with:\n"
                    '- "summary": a concise 2-3 sentence summary\n'
                    '- "action_items": array of action items extracted\n'
                    '- "key_topics": array of main topics discussed\n'
                    '- "memories": array of facts worth remembering about the speakers\n'
                    "Respond ONLY with valid JSON, no markdown."
                ),
            },
            {"role": "user", "content": f"Transcript:\n\n{transcript}"},
        ]
        
        try:
            result = await self.chat(messages, temperature=0.3)
            import json
            try:
                # Try to parse JSON response
                return json.loads(result.strip().removeprefix("```json").removesuffix("```").strip())
            except json.JSONDecodeError:
                # If not valid JSON, return structured response
                logger.warning(f"LLM returned non-JSON response: {result[:100]}")
                return {
                    "summary": result,
                    "action_items": [],
                    "key_topics": [],
                    "memories": []
                }
        except Exception as e:
            logger.error(f"Conversation summarization failed: {e}")
            return {
                "summary": "",
                "action_items": [],
                "key_topics": [],
                "memories": []
            }
    
    async def embed(self, text: str) -> List[float]:
        """Get embedding vector for text."""
        try:
            response = await self.client.embeddings.create(
                model=self.embedding_model,
                input=text,
            )
            return response.data[0].embedding
        except Exception as e:
            logger.error(f"Embedding generation failed: {e}")
            # Return zero vector as fallback
            return [0.0] * 768
    
    async def health_check(self) -> bool:
        """Check if Ollama service is healthy."""
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                response = await client.get(f"{settings.ollama_url}/api/tags")
                return response.status_code == 200
        except Exception as e:
            logger.warning(f"Ollama health check failed: {e}")
            return False


# =============================================================================
# MinIO (Object Storage)
# =============================================================================
class StorageService:
    """MinIO S3-compatible object storage."""
    
    def __init__(self):
        # Defensively append port if endpoint has no port
        minio_endpoint = settings.minio_endpoint
        if ":" not in minio_endpoint:
            minio_endpoint = f"{minio_endpoint}:{settings.minio_port}"
        
        self.client = Minio(
            minio_endpoint,
            access_key=settings.minio_root_user,
            secret_key=settings.minio_root_password,
            secure=settings.minio_secure,
        )
        self._ensure_buckets()
    
    def _ensure_buckets(self):
        """Ensure required buckets exist."""
        buckets = [
            settings.minio_bucket_audio,
            settings.minio_bucket_profiles,
            settings.minio_bucket_backups,
        ]
        for bucket in buckets:
            if not self.client.bucket_exists(bucket):
                try:
                    self.client.make_bucket(bucket)
                    logger.info(f"Created bucket: {bucket}")
                except S3Error as e:
                    logger.error(f"Failed to create bucket {bucket}: {e}")
    
    def upload_audio(self, object_name: str, data: bytes, content_type: str = "audio/opus") -> str:
        """Upload audio file to MinIO."""
        try:
            self.client.put_object(
                settings.minio_bucket_audio,
                object_name,
                io.BytesIO(data),
                len(data),
                content_type=content_type,
            )
            return f"{settings.minio_bucket_audio}/{object_name}"
        except S3Error as e:
            logger.error(f"Failed to upload audio {object_name}: {e}")
            raise Exception(f"Audio upload failed: {e}")
    
    def get_audio(self, object_name: str) -> bytes:
        """Download audio file from MinIO."""
        try:
            response = self.client.get_object(settings.minio_bucket_audio, object_name)
            return response.read()
        except S3Error as e:
            logger.error(f"Failed to download audio {object_name}: {e}")
            raise Exception(f"Audio download failed: {e}")
    
    def delete_audio(self, object_name: str) -> bool:
        """Delete audio file from MinIO."""
        try:
            self.client.remove_object(settings.minio_bucket_audio, object_name)
            return True
        except S3Error as e:
            logger.error(f"Failed to delete audio {object_name}: {e}")
            return False
    
    def list_audio_files(self, prefix: str = "") -> List[str]:
        """List audio files in the bucket."""
        try:
            objects = self.client.list_objects(settings.minio_bucket_audio, prefix=prefix)
            return [obj.object_name for obj in objects]
        except S3Error as e:
            logger.error(f"Failed to list audio files: {e}")
            return []
    
    async def health_check(self) -> bool:
        """Check if MinIO service is healthy."""
        try:
            # Try to list buckets
            self.client.list_buckets()
            return True
        except Exception as e:
            logger.warning(f"MinIO health check failed: {e}")
            return False


# =============================================================================
# Qdrant (Vector Database)
# =============================================================================
class VectorService:
    """Qdrant vector database for semantic memory search."""
    
    EMBEDDING_DIM = 768  # nomic-embed-text dimension
    
    def __init__(self):
        self.client = QdrantClient(
            host=settings.qdrant_host,
            port=settings.qdrant_port,
            api_key=settings.qdrant_api_key or None,
        )
        self.collection = settings.qdrant_collection
        self._ensure_collection()
    
    def _ensure_collection(self):
        """Ensure the collection exists."""
        try:
            collections = [c.name for c in self.client.get_collections().collections]
            if self.collection not in collections:
                self.client.create_collection(
                    collection_name=self.collection,
                    vectors_config=VectorParams(
                        size=self.EMBEDDING_DIM,
                        distance=Distance.COSINE,
                    ),
                )
                logger.info(f"Created collection: {self.collection}")
        except Exception as e:
            logger.error(f"Failed to ensure collection {self.collection}: {e}")
    
    def upsert(self, point_id: str, vector: List[float], payload: Dict[str, Any]):
        """Upsert a vector point."""
        try:
            self.client.upsert(
                collection_name=self.collection,
                points=[PointStruct(id=point_id, vector=vector, payload=payload)],
            )
        except Exception as e:
            logger.error(f"Failed to upsert point {point_id}: {e}")
            raise Exception(f"Vector upsert failed: {e}")
    
    def search(self, vector: List[float], limit: int = 10, filter_dict: Optional[Dict] = None) -> List[Any]:
        """Search for similar vectors."""
        try:
            if filter_dict:
                # Convert filter dict to Qdrant Filter
                filter_conditions = []
                for key, value in filter_dict.items():
                    filter_conditions.append(
                        MustCondition(
                            condition=MatchValue(
                                key=key,
                                value=value,
                            )
                        )
                    )
                qdrant_filter = Filter(must=filter_conditions)
            else:
                qdrant_filter = None
            
            results = self.client.query_points(
                collection_name=self.collection,
                query=vector,
                limit=limit,
                query_filter=qdrant_filter,
            )
            return results.points
        except Exception as e:
            logger.error(f"Vector search failed: {e}")
            return []
    
    def delete(self, point_id: str) -> bool:
        """Delete a vector point."""
        try:
            self.client.delete(
                collection_name=self.collection,
                points_selector={"ids": [point_id]},
            )
            return True
        except Exception as e:
            logger.error(f"Failed to delete point {point_id}: {e}")
            return False
    
    async def health_check(self) -> bool:
        """Check if Qdrant service is healthy."""
        try:
            self.client.get_collections()
            return True
        except Exception as e:
            logger.warning(f"Qdrant health check failed: {e}")
            return False


# =============================================================================
# Redis (Cache)
# =============================================================================
def get_redis() -> Redis:
    """Get Redis connection."""
    return Redis(
        host=settings.redis_host,
        port=settings.redis_port,
        password=settings.redis_password,
        decode_responses=True,
    )


async def redis_health_check() -> bool:
    """Check if Redis service is healthy."""
    try:
        redis = get_redis()
        await redis.ping()
        await redis.close()
        return True
    except Exception as e:
        logger.warning(f"Redis health check failed: {e}")
        return False


# =============================================================================
# Meilisearch (Search)
# =============================================================================
class SearchService:
    """Meilisearch full-text search."""
    
    def __init__(self):
        import meilisearch
        self.client = meilisearch.Client(
            settings.meilisearch_url,
            settings.meilisearch_key,
        )
    
    async def search(self, query: str, index: str = "conversations", limit: int = 10) -> List[Dict[str, Any]]:
        """Search in a Meilisearch index."""
        try:
            results = self.client.index(index).search(query, limit=limit)
            return results.get("hits", [])
        except Exception as e:
            logger.error(f"Search failed: {e}")
            return []
    
    async def add_document(self, index: str, document: Dict[str, Any]) -> bool:
        """Add a document to a Meilisearch index."""
        try:
            self.client.index(index).add_documents([document])
            return True
        except Exception as e:
            logger.error(f"Failed to add document to {index}: {e}")
            return False
    
    async def health_check(self) -> bool:
        """Check if Meilisearch service is healthy."""
        try:
            self.client.health()
            return True
        except Exception as e:
            logger.warning(f"Meilisearch health check failed: {e}")
            return False


# =============================================================================
# Service Registry
# =============================================================================
class ServiceRegistry:
    """Central registry for all services."""
    
    def __init__(self):
        self.whisper = WhisperService()
        self.llm = LLMService()
        self.storage = StorageService()
        self.vectors = VectorService()
        self.search = SearchService()
        self.redis = get_redis()
    
    async def health_check_all(self) -> Dict[str, bool]:
        """Check health of all services."""
        results = {}
        
        # Check each service
        results["whisper"] = await self.whisper.health_check()
        results["ollama"] = await self.llm.health_check()
        results["storage"] = await self.storage.health_check()
        results["vectors"] = await self.vectors.health_check()
        results["redis"] = await redis_health_check()
        results["search"] = await self.search.health_check()
        
        return results
    
    async def close(self):
        """Close all service connections."""
        await self.redis.close()
