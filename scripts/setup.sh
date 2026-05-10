#!/bin/bash

# Omi Omni Setup Script
# This script initializes the backend services and downloads required models

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if .env file exists
if [ ! -f "../.env" ]; then
    print_error ".env file not found. Please copy .env.example to .env and configure it."
    exit 1
fi

# Load environment variables
set -a
source ../.env
set +a

print_status "Starting Omi Omni setup..."

# =============================================================================
# Step 1: Check Docker and Docker Compose
# =============================================================================
print_status "Checking Docker installation..."

if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed. Please install Docker first."
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    print_error "Docker Compose is not installed. Please install Docker Compose."
    exit 1
fi

print_success "Docker and Docker Compose are installed."

# =============================================================================
# Step 2: Determine GPU type and select appropriate compose file
# =============================================================================
print_status "Detecting GPU type..."

COMPOSE_FILE="../docker/docker-compose.yml"

# Check for NVIDIA GPU
if command -v nvidia-smi &> /dev/null; then
    print_success "NVIDIA GPU detected. Using CUDA configuration."
    COMPOSE_FILE="../docker/docker-compose.yml"
    
# Check for AMD GPU (ROCm)
elif command -v rocminfo &> /dev/null; then
    print_success "AMD GPU detected. Using ROCm configuration."
    COMPOSE_FILE="../docker/docker-compose-amd.yml"
    
    # Check if HSA_OVERRIDE_GFX_VERSION is set in .env
    if [ -z "$HSA_OVERRIDE_GFX_VERSION" ]; then
        print_warning "HSA_OVERRIDE_GFX_VERSION not set in .env. Setting to 10.3.0 for RX 7900 XTX."
        export HSA_OVERRIDE_GFX_VERSION=10.3.0
    fi
else
    print_warning "No GPU detected. Using CPU-only configuration."
    print_warning "Performance will be significantly slower without GPU acceleration."
    COMPOSE_FILE="../docker/docker-compose.yml"
fi

print_status "Using compose file: $COMPOSE_FILE"

# =============================================================================
# Step 3: Start Docker services
# =============================================================================
print_status "Starting Docker services..."

cd ..
docker compose -f $COMPOSE_FILE up -d

# Wait for services to be healthy
print_status "Waiting for services to initialize..."

MAX_ATTEMPTS=30
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))
    
    # Check backend health
    if curl -s http://localhost:${BACKEND_PORT:-8000}/health | grep -q '"status": "healthy"'; then
        print_success "Backend is healthy!"
        break
    fi
    
    if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
        print_error "Backend did not become healthy after $MAX_ATTEMPTS attempts."
        print_status "Checking individual services..."
        docker compose -f $COMPOSE_FILE ps
        exit 1
    fi
    
    print_status "Attempt $ATTEMPT/$MAX_ATTEMPTS: Waiting for backend to be healthy..."
    sleep 10
done

# =============================================================================
# Step 4: Download AI Models
# =============================================================================
print_status "Downloading AI models..."

# Download Whisper model
print_status "Downloading Whisper model: $WHISPER_MODEL..."
if curl -s -X POST http://localhost:${WHISPER_PORT:-8001}/v1/audio/transcriptions \
    -F file=@/dev/null \
    -F model="$WHISPER_MODEL" \
    -F response_format=json > /dev/null 2>&1; then
    print_success "Whisper model downloaded successfully."
else
    print_warning "Whisper model download may have failed. It will be downloaded on first use."
fi

# Download Ollama models
print_status "Downloading Ollama models..."

# Function to pull Ollama model
pull_ollama_model() {
    local model=$1
    print_status "Pulling Ollama model: $model..."
    
    if curl -s -X POST http://localhost:${OLLAMA_PORT:-11434}/api/pull \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"$model\"}" > /dev/null 2>&1; then
        print_success "Ollama model $model downloaded successfully."
    else
        print_warning "Ollama model $model download may have failed. Will retry on first use."
    fi
}

# Pull main LLM model
pull_ollama_model "$OLLAMA_MODEL"

# Pull embedding model
pull_ollama_model "nomic-embed-text"

# =============================================================================
# Step 5: Initialize Database
# =============================================================================
print_status "Initializing database..."

# Create default user if not exists
PSQL_CMD="psql -h localhost -p ${POSTGRES_PORT:-5432} -U ${POSTGRES_USER:-omi} -d ${POSTGRES_DB:-omi} -c"

# Check if default user exists
if $PSQL_CMD "SELECT 1 FROM users WHERE username = 'default'" | grep -q "1 row"; then
    print_success "Default user already exists."
else
    print_status "Creating default user..."
    # The init-db.sql script should have created this, but just in case
    docker compose -f $COMPOSE_FILE exec postgres psql -U ${POSTGRES_USER:-omi} -d ${POSTGRES_DB:-omi} -c \
        "INSERT INTO users (username, email, created_at, updated_at) VALUES ('default', 'default@omi-omni.local', NOW(), NOW()) ON CONFLICT DO NOTHING;"
    print_success "Default user created."
fi

# =============================================================================
# Step 6: Verify all services
# =============================================================================
print_status "Verifying all services..."

# Check each service
SERVICES=("postgres" "redis" "qdrant" "minio" "meilisearch" "whisper" "ollama" "backend")

for service in "${SERVICES[@]}"; do
    case $service in
        "postgres")
            if pg_isready -h localhost -p ${POSTGRES_PORT:-5432} -U ${POSTGRES_USER:-omi} > /dev/null 2>&1; then
                print_success "PostgreSQL is running."
            else
                print_error "PostgreSQL is not running."
            fi
            ;;
        "redis")
            if redis-cli -h localhost -p ${REDIS_PORT:-6379} -a ${REDIS_PASSWORD:-changeme} ping | grep -q "PONG"; then
                print_success "Redis is running."
            else
                print_error "Redis is not running."
            fi
            ;;
        "qdrant")
            if curl -s http://localhost:${QDRANT_PORT:-6333}/readyz | grep -q "true"; then
                print_success "Qdrant is running."
            else
                print_error "Qdrant is not running."
            fi
            ;;
        "minio")
            if curl -s http://localhost:${MINIO_PORT:-9000}/minio/health/live | grep -q "ok"; then
                print_success "MinIO is running."
            else
                print_error "MinIO is not running."
            fi
            ;;
        "meilisearch")
            if curl -s http://localhost:${MEILISEARCH_PORT:-7700}/health | grep -q '"status":"available"'; then
                print_success "Meilisearch is running."
            else
                print_error "Meilisearch is not running."
            fi
            ;;
        "whisper")
            if curl -s http://localhost:${WHISPER_PORT:-8001}/health | grep -q "ok"; then
                print_success "Whisper is running."
            else
                print_error "Whisper is not running."
            fi
            ;;
        "ollama")
            if curl -s http://localhost:${OLLAMA_PORT:-11434}/api/tags | grep -q "models"; then
                print_success "Ollama is running."
            else
                print_error "Ollama is not running."
            fi
            ;;
        "backend")
            if curl -s http://localhost:${BACKEND_PORT:-8000}/health | grep -q '"status": "healthy"'; then
                print_success "Backend is running and healthy."
            else
                print_error "Backend is not healthy."
            fi
            ;;
    esac
done

# =============================================================================
# Step 7: Display summary
# =============================================================================
print_success ""
print_success "=========================================="
print_success "Omi Omni Setup Complete!"
print_success "=========================================="
print_status ""
print_status "Backend URL: http://localhost:${BACKEND_PORT:-8000}"
print_status "API Key: $API_KEY"
print_status ""
print_status "Service URLs:"
print_status "  - Backend: http://localhost:${BACKEND_PORT:-8000}"
print_status "  - Whisper: http://localhost:${WHISPER_PORT:-8001}"
print_status "  - Ollama: http://localhost:${OLLAMA_PORT:-11434}"
print_status "  - Qdrant: http://localhost:${QDRANT_PORT:-6333}"
print_status "  - MinIO Console: http://localhost:${MINIO_CONSOLE_PORT:-9001}"
print_status "  - Meilisearch: http://localhost:${MEILISEARCH_PORT:-7700}"
print_status ""
print_status "To test the backend:"
print_status "  curl http://localhost:${BACKEND_PORT:-8000}/health"
print_status ""
print_status "To run the mobile app:"
print_status "  cd app && flutter run"
print_status ""
print_success "Ready to use Omi Omni!"
