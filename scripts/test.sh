#!/bin/bash

# Omi Omni Test Script
# Runs tests for the backend and mobile app

set -e

echo "=========================================="
echo "Omi Omni Test Suite"
echo "=========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

# Check if .env file exists
if [ ! -f "../.env" ]; then
    warn ".env file not found. Using defaults for testing."
fi

# Load environment variables
set -a
source ../.env 2>/dev/null || true
set +a

# =============================================================================
# Backend Tests
# =============================================================================
info "Running Backend Tests..."

# Test 1: Check if backend container is running
info "Test 1: Checking backend container..."
if docker compose -f ../docker/docker-compose.yml ps | grep -q "omi-omni-backend"; then
    pass "Backend container is running"
else
    warn "Backend container is not running. Starting it for tests..."
    docker compose -f ../docker/docker-compose.yml up -d --wait
    sleep 10
fi

# Test 2: Health check endpoint
info "Test 2: Testing health check endpoint..."
if curl -s http://localhost:${BACKEND_PORT:-8000}/health | grep -q '"status": "healthy"'; then
    pass "Health check endpoint is working"
else
    fail "Health check endpoint failed"
fi

# Test 3: Check all services are healthy
info "Test 3: Checking all services..."
HEALTH_RESPONSE=$(curl -s http://localhost:${BACKEND_PORT:-8000}/health)
if echo "$HEALTH_RESPONSE" | grep -q '"postgres": "ok"' && \
   echo "$HEALTH_RESPONSE" | grep -q '"whisper": true' && \
   echo "$HEALTH_RESPONSE" | grep -q '"ollama": true' && \
   echo "$HEALTH_RESPONSE" | grep -q '"storage": true' && \
   echo "$HEALTH_RESPONSE" | grep -q '"vectors": true' && \
   echo "$HEALTH_RESPONSE" | grep -q '"redis": true'; then
    pass "All services are healthy"
else
    warn "Some services are not healthy: $HEALTH_RESPONSE"
fi

# Test 4: Stats endpoint
info "Test 4: Testing stats endpoint..."
if curl -s http://localhost:${BACKEND_PORT:-8000}/v1/stats | grep -q '"conversations"'; then
    pass "Stats endpoint is working"
else
    fail "Stats endpoint failed"
fi

# =============================================================================
# Backend API Tests
# =============================================================================
info "Running Backend API Tests..."

# Test API key authentication
API_KEY=${API_KEY:-change-me}

# Test 5: List conversations (should work with valid API key)
info "Test 5: Testing conversations endpoint..."
if curl -s -H "Authorization: Bearer $API_KEY" http://localhost:${BACKEND_PORT:-8000}/v1/conversations | grep -q '[]'; then
    pass "Conversations endpoint is working"
else
    fail "Conversations endpoint failed"
fi

# Test 6: List memories
info "Test 6: Testing memories endpoint..."
if curl -s -H "Authorization: Bearer $API_KEY" http://localhost:${BACKEND_PORT:-8000}/v1/memories | grep -q '[]'; then
    pass "Memories endpoint is working"
else
    fail "Memories endpoint failed"
fi

# Test 7: Get config
info "Test 7: Testing config endpoint..."
if curl -s -H "Authorization: Bearer $API_KEY" http://localhost:${BACKEND_PORT:-8000}/v1/config | grep -q 'whisper_model'; then
    pass "Config endpoint is working"
else
    fail "Config endpoint failed"
fi

# =============================================================================
# WebSocket Test
# =============================================================================
info "Running WebSocket Test..."

# Test 8: WebSocket connection
info "Test 8: Testing WebSocket connection..."
if timeout 5 bash -c "echo '{"type": \"ping\"}' | websocat -H \"Authorization: Bearer \$API_KEY\" ws://localhost:\${BACKEND_PORT:-8000}/ws/audio" 2>/dev/null | grep -q 'pong'; then
    pass "WebSocket connection is working"
else
    warn "WebSocket connection test failed (websocat may not be installed)"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "=========================================="
echo "Test Suite Complete"
echo "=========================================="
echo ""
echo "All critical tests passed!"
echo ""
echo "Next steps:"
echo "1. Run the mobile app: cd app && flutter run"
echo "2. Connect your Omi device"
echo "3. Start recording and test the full pipeline"
