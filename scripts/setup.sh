#!/bin/bash
set -e

if [ "$(id -u)" -eq 0 ]; then
    echo "ERROR: Please do not run this script as root."
    exit 1
fi

echo "=== Omi Omni Setup ==="
echo ""

echo "Creating data directories..."
mkdir -p data/postgres data/qdrant data/minio data/redis data/meilisearch models/whisper models/llm

if [ ! -f .env ]; then
    echo "Creating .env file from template..."
    cp .env.example .env
    API_KEY=$(openssl rand -hex 32)
    POSTGRES_PASSWORD=$(openssl rand -hex 16)
    MINIO_ROOT_PASSWORD=$(openssl rand -hex 16)
    MEILI_MASTER_KEY=$(openssl rand -hex 32)
    sed -i "s/^API_KEY=.*/API_KEY=$API_KEY/" .env
    sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$POSTGRES_PASSWORD/" .env
    sed -i "s/^MINIO_ROOT_PASSWORD=.*/MINIO_ROOT_PASSWORD=$MINIO_ROOT_PASSWORD/" .env
    sed -i "s/^MEILI_MASTER_KEY=.*/MEILI_MASTER_KEY=$MEILI_MASTER_KEY/" .env
    echo "Generated secure credentials in .env"
else
    echo "Using existing .env file"
fi

source .env

echo "Checking Docker installation..."
if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker is not installed."
    exit 1
fi
echo "Docker is installed"

echo "Detecting GPU..."
if lspci | grep -qi amd || lshw -c display | grep -qi amd 2>/dev/null; then
    GPU_TYPE="amd"
    COMPOSE_FILE="docker/docker-compose-amd.yml"
    echo "AMD GPU detected - using ROCm"
else
    GPU_TYPE="nvidia"
    COMPOSE_FILE="docker/docker-compose.yml"
    echo "NVIDIA GPU assumed - using CUDA"
fi

echo ""
echo "Downloading Whisper model..."
if [ ! -f "models/whisper/ggml-medium.bin" ]; then
    echo "Model not found. Please download manually:"
    echo "  wget -O models/whisper/ggml-medium.bin https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin"
    echo "Or use the download script in scripts/download-models.sh"
    exit 1
else
    echo "Whisper model already exists"
fi

echo "Initializing database..."
if [ ! -f "data/postgres/initialized" ]; then
    echo "Starting temporary PostgreSQL container..."
    docker run -d --name temp_postgres \
        -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
        -e POSTGRES_USER=omi \
        -e POSTGRES_DB=omi \
        -v $(pwd)/data/postgres:/var/lib/postgresql/data \
        -p 5432:5432 \
        postgres:16-alpine > /dev/null 2>&1
    
    echo "Waiting for PostgreSQL to start..."
    for i in {1..30}; do
        if docker exec temp_postgres pg_isready -U omi -d omi 2>&1 | grep -q "accepting connections"; then
            break
        fi
        sleep 1
    done
    
    echo "Running database initialization..."
    docker exec -i temp_postgres psql -U omi -d omi < scripts/init-db.sql 2>&1
    touch data/postgres/initialized
    docker stop temp_postgres > /dev/null 2>&1 || true
    docker rm temp_postgres > /dev/null 2>&1 || true
    echo "Database initialized"
else
    echo "Database already initialized, skipping..."
fi

echo "Creating Docker environment file..."
mkdir -p docker

API_KEY_VALUE=$(grep "^API_KEY=" .env | cut -d'=' -f2-)
POSTGRES_PASSWORD_VALUE=$(grep "^POSTGRES_PASSWORD=" .env | cut -d'=' -f2-)
MINIO_ROOT_PASSWORD_VALUE=$(grep "^MINIO_ROOT_PASSWORD=" .env | cut -d'=' -f2-)
MEILI_MASTER_KEY_VALUE=$(grep "^MEILI_MASTER_KEY=" .env | cut -d'=' -f2-)

cat > docker/.env << DOCKERENV
API_KEY=$API_KEY_VALUE
POSTGRES_PASSWORD=$POSTGRES_PASSWORD_VALUE
POSTGRES_USER=omi
POSTGRES_DB=omi
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=$MINIO_ROOT_PASSWORD_VALUE
MEILI_MASTER_KEY=$MEILI_MASTER_KEY_VALUE
REDIS_PASSWORD=
WHISPER_MODEL_PATH=/models/ggml-medium.bin
OLLAMA_MODELS_PATH=/root/.ollama/models
DOCKERENV

if [ "$GPU_TYPE" = "amd" ]; then
    echo "HSA_OVERRIDE_GFX_VERSION=10.3.0" >> docker/.env
fi

echo ""
echo "=========================================="
echo "  Omi Omni Setup Complete!"
echo "=========================================="
echo ""
echo "To start the backend, run:"
echo "  docker compose -f $COMPOSE_FILE up -d"
echo ""
echo "Backend will be available at: http://localhost:8000"
echo ""
echo "API Key: $API_KEY_VALUE"
echo ""
echo "To get the APK: Check GitHub Actions or run: cd app && flutter build apk --release"
echo ""
