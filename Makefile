# Omi Omni - Makefile for common tasks
# Usage: make <target>

.PHONY: help setup start stop restart backend apk clean

# Default compose file
COMPOSE_FILE ?= docker/docker-compose.yml

help: ## Show this help message
	@echo "Omi Omni - Available Commands:"
	@echo ""
	@echo "  make setup          - Run full setup (creates env, downloads models, init DB)"
	@echo "  make start          - Start all backend services"
	@echo "  make stop           - Stop all backend services"
	@echo "  make restart        - Restart all backend services"
	@echo "  make backend        - Start only the backend API"
	@echo "  make apk            - Build Android APK"
	@echo "  make clean          - Remove all containers and volumes"
	@echo "  make clean-all      - Full cleanup (containers, volumes, data)"
	@echo ""
	@echo "AMD GPU Users:"
	@echo "  make start-amd      - Start with AMD/ROCm configuration"
	@echo ""
	@echo "Environment Variables:"
	@echo "  COMPOSE_FILE        - Docker compose file to use (default: docker/docker-compose.yml)"

# Detect GPU type
GPU_TYPE := $(shell lspci 2>/dev/null | grep -qi amd && echo "amd" || echo "nvidia")

setup: ## Run full setup
	@echo "=== Omi Omni Setup ==="
	@echo ""
	@mkdir -p data/postgres data/qdrant data/minio data/redis data/meilisearch models/whisper models/llm docker
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		API_KEY=$$(openssl rand -hex 32); \
		POSTGRES_PASSWORD=$$(openssl rand -hex 16); \
		MINIO_ROOT_PASSWORD=$$(openssl rand -hex 16); \
		MEILI_MASTER_KEY=$$(openssl rand -hex 32); \
		sed -i "s/^API_KEY=.*/API_KEY=$$API_KEY/" .env; \
		sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$$POSTGRES_PASSWORD/" .env; \
		sed -i "s/^MINIO_ROOT_PASSWORD=.*/MINIO_ROOT_PASSWORD=$$MINIO_ROOT_PASSWORD/" .env; \
		sed -i "s/^MEILI_MASTER_KEY=.*/MEILI_MASTER_KEY=$$MEILI_MASTER_KEY/" .env; \
		echo "Generated .env with secure credentials"; \
	fi
	@source .env && \
	if [ "$(GPU_TYPE)" = "amd" ]; then \
		COMPOSE_FILE="docker/docker-compose-amd.yml"; \
		echo "AMD GPU detected - using ROCm configuration"; \
	else \
		COMPOSE_FILE="docker/docker-compose.yml"; \
		echo "Using standard configuration"; \
	fi
	@echo ""
	@echo "Downloading Whisper model..."
	@if [ ! -f "models/whisper/ggml-medium.bin" ]; then \
		echo "Please download Whisper model manually:"; \
		echo "  wget -O models/whisper/ggml-medium.bin https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin"; \
		exit 1; \
	else \
		echo "Whisper model found"; \
	fi
	@echo ""
	@echo "Initializing database..."
	@if [ ! -f "data/postgres/initialized" ]; then \
		docker run -d --name temp_postgres \
			-e POSTGRES_PASSWORD=$$POSTGRES_PASSWORD \
			-e POSTGRES_USER=omi \
			-e POSTGRES_DB=omi \
			-v $$(pwd)/data/postgres:/var/lib/postgresql/data \
			-p 5432:5432 \
			postgres:16-alpine > /dev/null 2>&1; \
		echo "Waiting for PostgreSQL..."; \
		for i in {1..30}; do \
			docker exec temp_postgres pg_isready -U omi -d omi 2>&1 | grep -q "accepting connections" && break || true; \
			sleep 1; \
		done; \
		echo "Initializing database schema..."; \
		docker exec -i temp_postgres psql -U omi -d omi < scripts/init-db.sql 2>&1; \
		touch data/postgres/initialized; \
		docker stop temp_postgres > /dev/null 2>&1 || true; \
		docker rm temp_postgres > /dev/null 2>&1 || true; \
		echo "Database initialized"; \
	else \
		echo "Database already initialized"; \
	fi
	@echo ""
	@echo "Creating docker/.env..."
	@API_KEY_VALUE=$$(grep "^API_KEY=" .env | cut -d'=' -f2-); \
	POSTGRES_PASSWORD_VALUE=$$(grep "^POSTGRES_PASSWORD=" .env | cut -d'=' -f2-); \
	MINIO_ROOT_PASSWORD_VALUE=$$(grep "^MINIO_ROOT_PASSWORD=" .env | cut -d'=' -f2-); \
	MEILI_MASTER_KEY_VALUE=$$(grep "^MEILI_MASTER_KEY=" .env | cut -d'=' -f2-); \
	{ \
		echo "API_KEY=$$API_KEY_VALUE"; \
		echo "POSTGRES_PASSWORD=$$POSTGRES_PASSWORD_VALUE"; \
		echo "POSTGRES_USER=omi"; \
		echo "POSTGRES_DB=omi"; \
		echo "MINIO_ROOT_USER=minioadmin"; \
		echo "MINIO_ROOT_PASSWORD=$$MINIO_ROOT_PASSWORD_VALUE"; \
		echo "MEILI_MASTER_KEY=$$MEILI_MASTER_KEY_VALUE"; \
		echo "REDIS_PASSWORD="; \
		echo "WHISPER_MODEL_PATH=/models/ggml-medium.bin"; \
		echo "OLLAMA_MODELS_PATH=/root/.ollama/models"; \
		if [ "$(GPU_TYPE)" = "amd" ]; then \
			echo "HSA_OVERRIDE_GFX_VERSION=10.3.0"; \
		fi \
	} > docker/.env
	@echo ""
	@echo "=== Setup Complete ==="
	@echo ""
	@echo "To start: make start"

start: ## Start all backend services
	@echo "Starting backend services..."
	@if [ "$(GPU_TYPE)" = "amd" ]; then \
		COMPOSE_FILE="docker/docker-compose-amd.yml"; \
	fi
	docker compose -f $(COMPOSE_FILE) up -d
	@echo ""
	@echo "Backend available at: http://localhost:8000"

start-amd: ## Start with AMD/ROCm configuration
	@echo "Starting with AMD ROCm configuration..."
	docker compose -f docker/docker-compose-amd.yml up -d
	@echo ""
	@echo "Backend available at: http://localhost:8000"

stop: ## Stop all backend services
	docker compose -f $(COMPOSE_FILE) down

restart: ## Restart all backend services
	make stop
	sleep 2
	make start

backend: ## Start only the backend API
	docker compose -f $(COMPOSE_FILE) up -d backend

apk: ## Build Android APK
	cd app && \
	flutter pub get && \
	flutter build apk --release && \
	mv build/app/outputs/flutter-apk/app-release.apk ../../omi-omni-release.apk && \
	cd .. && \
	echo "APK built: omi-omni-release.apk"

clean: ## Remove containers and volumes
	docker compose -f $(COMPOSE_FILE) down -v

clean-all: ## Full cleanup
	make clean
	rm -rf data/* models/*
	echo "All data and models removed"
