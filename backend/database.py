"""
Omi Omni Database Configuration
===============================
SQLAlchemy async database configuration and models.
"""

import logging
from typing import AsyncGenerator
from sqlalchemy import Column, Integer, String, Text, DateTime, JSON, ForeignKey, Float, func, select
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker, relationship

from config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()

# Database URL
DATABASE_URL = f"postgresql+asyncpg://{settings.postgres_user}:{settings.postgres_password}@{settings.postgres_host}:{settings.postgres_port}/{settings.postgres_db}"

# Create async engine
engine = create_async_engine(DATABASE_URL, echo=settings.debug)

# Session factory
async_session = sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


# =============================================================================
# Database Models
# =============================================================================
Base = declarative_base()


class User(Base):
    """User model for multi-user support."""
    __tablename__ = "users"
    
    id = Column(Integer, primary_key=True, index=True)
    username = Column(String(50), unique=True, nullable=False)
    email = Column(String(255), unique=True, nullable=True)
    hashed_password = Column(String(255), nullable=True)
    api_key = Column(String(255), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
    
    # Relationships
    conversations = relationship("Conversation", back_populates="user")
    memories = relationship("Memory", back_populates="user")


class Conversation(Base):
    """Conversation model for storing transcribed conversations."""
    __tablename__ = "conversations"
    
    id = Column(String(36), primary_key=True, index=True)  # UUID
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    title = Column(String(255), nullable=True)
    status = Column(String(20), default="processing")  # processing, completed, failed
    started_at = Column(DateTime(timezone=True), nullable=True)
    finished_at = Column(DateTime(timezone=True), nullable=True)
    transcript = Column(Text, nullable=True)
    summary = Column(Text, nullable=True)
    action_items = Column(JSON, nullable=True)  # List of action items
    key_topics = Column(JSON, nullable=True)  # List of key topics
    audio_path = Column(String(500), nullable=True)  # Path in MinIO
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    # Relationships
    user = relationship("User", back_populates="conversations")
    segments = relationship("ConversationSegment", back_populates="conversation")
    memories = relationship("Memory", back_populates="conversation")


class ConversationSegment(Base):
    """Individual segments of a conversation for detailed analysis."""
    __tablename__ = "conversation_segments"
    
    id = Column(Integer, primary_key=True, index=True)
    conversation_id = Column(String(36), ForeignKey("conversations.id"), nullable=False)
    text = Column(Text, nullable=False)
    start_time = Column(Integer, nullable=True)  # Start time in seconds
    end_time = Column(Integer, nullable=True)  # End time in seconds
    confidence = Column(Float, nullable=True)  # Confidence score
    segment_index = Column(Integer, nullable=True)  # Order in conversation
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    # Relationships
    conversation = relationship("Conversation", back_populates="segments")


class Memory(Base):
    """Memories extracted from conversations for semantic search."""
    __tablename__ = "memories"
    
    id = Column(String(36), primary_key=True, index=True)  # UUID
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    conversation_id = Column(String(36), ForeignKey("conversations.id"), nullable=True)
    content = Column(Text, nullable=False)
    embedding_id = Column(String(36), nullable=True)  # ID in Qdrant
    category = Column(String(50), nullable=True)  # e.g., conversation, note, action_item
    memory_metadata = Column("metadata", JSON, nullable=True)  # Additional metadata
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    # Relationships
    user = relationship("User", back_populates="memories")
    conversation = relationship("Conversation", back_populates="memories")


class Device(Base):
    """Omi device information."""
    __tablename__ = "devices"
    
    id = Column(String(36), primary_key=True, index=True)  # Device UUID
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    name = Column(String(100), nullable=True)
    device_type = Column(String(50), nullable=True)  # omi, frame, etc.
    firmware_version = Column(String(50), nullable=True)
    battery_level = Column(Integer, nullable=True)
    last_seen_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    # Relationships
    user = relationship("User")


class Recording(Base):
    """Local recordings stored on the device."""
    __tablename__ = "recordings"
    
    id = Column(String(36), primary_key=True, index=True)  # UUID
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    device_id = Column(String(36), ForeignKey("devices.id"), nullable=True)
    file_path = Column(String(500), nullable=False)  # Local file path
    file_name = Column(String(255), nullable=True)
    duration = Column(Integer, nullable=True)  # Duration in seconds
    file_size = Column(Integer, nullable=True)  # File size in bytes
    codec = Column(String(20), nullable=True)  # Audio codec
    sample_rate = Column(Integer, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    # Relationships
    user = relationship("User")
    device = relationship("Device")


# =============================================================================
# Database Session Generator
# =============================================================================
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


# =============================================================================
# Database Initialization
# =============================================================================
async def init_db():
    """Initialize database tables."""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        logger.info("Database tables created")


async def drop_db():
    """Drop all database tables (for testing)."""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        logger.info("Database tables dropped")


# =============================================================================
# Utility Functions
# =============================================================================
async def get_or_create_user(db: AsyncSession, username: str = "default") -> User:
    """Get or create a default user."""
    result = await db.execute(
        select(User).where(User.username == username)
    )
    user = result.scalar_one_or_none()
    
    if not user:
        user = User(username=username)
        db.add(user)
        await db.commit()
        await db.refresh(user)
    
    return user
