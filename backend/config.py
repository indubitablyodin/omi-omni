"""
Omi Omni Backend Configuration
===============================
Centralized configuration management using Pydantic Settings.
"""

from functools import lru_cache
from typing import Optional
from pydantic import Field
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""
    
    # Backend Configuration
    backend_port: int = Field(default=8000, env="BACKEND_PORT")
    api_key: str = Field(default="change-me", env="API_KEY")
    debug: bool = Field(default=False, env="DEBUG")
    
    # Database (PostgreSQL)
    postgres_db: str = Field(default="omi", env="POSTGRES_DB")
    postgres_user: str = Field(default="omi", env="POSTGRES_USER")
    postgres_password: str = Field(default="change-me", env="POSTGRES_PASSWORD")
    postgres_port: int = Field(default=5432, env="POSTGRES_PORT")
    postgres_host: str = Field(default="postgres", env="POSTGRES_HOST")
    
    # Whisper (Speech-to-Text)
    whisper_port: int = Field(default=8001, env="WHISPER_PORT")
    whisper_model: str = Field(default="Systran/faster-whisper-large-v3", env="WHISPER_MODEL")
    whisper_url: str = Field(default="http://whisper:9000", env="WHISPER_URL")
    whisper_compute_type: str = Field(default="float16", env="WHISPER_COMPUTE_TYPE")
    
    # Ollama (LLM)
    ollama_port: int = Field(default=11434, env="OLLAMA_PORT")
    ollama_url: str = Field(default="http://ollama:11434", env="OLLAMA_URL")
    ollama_model: str = Field(default="qwen2.5:0.5b", env="OLLAMA_MODEL")
    ollama_keep_alive: str = Field(default="24h", env="OLLAMA_KEEP_ALIVE")
    ollama_max_loaded_models: int = Field(default=2, env="OLLAMA_MAX_LOADED_MODELS")
    
    # Qdrant (Vector Database)
    qdrant_port: int = Field(default=6333, env="QDRANT_PORT")
    qdrant_host: str = Field(default="qdrant", env="QDRANT_HOST")
    qdrant_api_key: Optional[str] = Field(default=None, env="QDRANT_API_KEY")
    qdrant_collection: str = Field(default="memories", env="QDRANT_COLLECTION")
    
    # MinIO (Object Storage)
    minio_port: int = Field(default=9000, env="MINIO_PORT")
    minio_console_port: int = Field(default=9001, env="MINIO_CONSOLE_PORT")
    minio_endpoint: str = Field(default="minio", env="MINIO_ENDPOINT")
    minio_secure: bool = Field(default=False, env="MINIO_SECURE")
    minio_root_user: str = Field(default="minioadmin", env="MINIO_ROOT_USER")
    minio_root_password: str = Field(default="change-me", env="MINIO_ROOT_PASSWORD")
    minio_bucket_audio: str = Field(default="omi-audio", env="MINIO_BUCKET_AUDIO")
    minio_bucket_profiles: str = Field(default="omi-profiles", env="MINIO_BUCKET_PROFILES")
    minio_bucket_backups: str = Field(default="omi-backups", env="MINIO_BUCKET_BACKUPS")
    
    # Redis (Cache)
    redis_port: int = Field(default=6379, env="REDIS_PORT")
    redis_host: str = Field(default="redis", env="REDIS_HOST")
    redis_password: str = Field(default="change-me", env="REDIS_PASSWORD")
    
    # Meilisearch (Search)
    meilisearch_port: int = Field(default=7700, env="MEILISEARCH_PORT")
    meilisearch_url: str = Field(default="http://meilisearch:7700", env="MEILISEARCH_URL")
    meilisearch_key: str = Field(default="change-me", env="MEILISEARCH_KEY")
    
    # Performance Tuning
    max_audio_chunk_size: int = Field(default=4096, env="MAX_AUDIO_CHUNK_SIZE")
    transcription_timeout: int = Field(default=120, env="TRANSCRIPTION_TIMEOUT")
    llm_timeout: int = Field(default=300, env="LLM_TIMEOUT")
    max_conversation_length: int = Field(default=60, env="MAX_CONVERSATION_LENGTH")
    
    # AMD GPU Configuration
    hsa_override_gfx_version: Optional[str] = Field(default=None, env="HSA_OVERRIDE_GFX_VERSION")
    rocm_path: Optional[str] = Field(default=None, env="ROCM_PATH")
    hip_path: Optional[str] = Field(default=None, env="HIP_PATH")
    
    # Docker Network
    docker_network: str = Field(default="omi-network", env="DOCKER_NETWORK")
    
    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = False


@lru_cache()
def get_settings() -> Settings:
    """Get cached settings instance."""
    return Settings()


# Convenience function to reload settings (useful for testing)
def reload_settings() -> Settings:
    """Reload settings, clearing the cache."""
    get_settings.cache_clear()
    return get_settings()
