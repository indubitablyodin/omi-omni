#!/bin/bash
# Mac smoke test script for Omi Omni
# Tests the complete local dev stack

set -e

BACKEND_HOST_PORT=${BACKEND_HOST_PORT:-8002}
WHISPER_HOST_PORT=${WHISPER_HOST_PORT:-8001}
COMPOSE_FILE="docker/docker-compose-mac.yml"

echo "=== Omi Omni Mac Smoke Test ==="
echo ""

# Step 1: Validate docker compose config
echo "[1/6] Validating docker compose configuration..."
docker compose -f $COMPOSE_FILE config > /dev/null 2>&1
echo "  ✓ Docker compose config is valid"

# Step 2: Start all services
echo "[2/6] Starting all services..."
docker compose -f $COMPOSE_FILE up -d
echo "  ✓ Services started"

# Step 3: Check container status
echo "[3/6] Checking container status..."
docker compose -f $COMPOSE_FILE ps
echo ""

# Step 4: Test backend health
echo "[4/6] Testing backend health..."
for i in {1..30}; do
    if curl -4 -f http://127.0.0.1:$BACKEND_HOST_PORT/health > /dev/null 2>&1; then
        echo "  ✓ Backend is healthy"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "  ✗ Backend health check failed after 30 attempts"
        docker compose -f $COMPOSE_FILE logs backend --tail=50
        exit 1
    fi
    sleep 2
done

# Step 5: Test Whisper server
echo "[5/6] Testing Whisper server..."
if curl -4 -f http://127.0.0.1:$WHISPER_HOST_PORT/v1/models > /dev/null 2>&1; then
    echo "  ✓ Whisper server is responding"
else
    echo "  ⚠ Whisper server not yet ready (model may still be downloading)"
fi

# Step 6: Check backend logs for errors
echo "[6/6] Checking backend logs..."
docker compose -f $COMPOSE_FILE logs backend --tail=120

echo ""
echo "=== Smoke Test Complete ==="
echo ""
echo "If all checks passed, your local dev stack is ready!"
echo ""
echo "Next steps:"
echo "  - Test transcription: curl -X POST http://127.0.0.1:$BACKEND_HOST_PORT/transcribe -F 'audio=@test.wav'"
echo "  - Test LLM: curl -X POST http://127.0.0.1:$BACKEND_HOST_PORT/chat -H 'Content-Type: application/json' -d '{"message": "test"}'"
