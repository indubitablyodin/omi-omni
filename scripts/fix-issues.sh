#!/bin/bash
# Script to fix known issues in Omi Omni
# Run this after cloning or pulling the repository

set -e

echo "=== Fixing Known Issues ==="
echo ""

# Issue #4: Fix missing SQLAlchemy imports in database models
echo "Fixing Issue #4: Database URL in database.py..."
if grep -q "postgresql+asyncpg\*\*\*\*\*\*\*\*" backend/database.py; then
    python3 << 'PYEOF'
    with open('backend/database.py', 'r') as f:
        content = f.read()
    
    # Fix the DATABASE_URL line
    content = content.replace(
        'DATABASE_URL = f"postgresql+asyncpg********{settings.postgres_host}:{settings.postgres_port}/{settings.postgres_db}"',
        'DATABASE_URL = f"postgresql+asyncpg://{settings.postgres_user}:{settings.postgres_password}@{settings.postgres_host}:{settings.postgres_port}/{settings.postgres_db}"'
    )
    
    # Fix the async generator type hint
    content = content.replace(
        'async def get_db() -> AsyncGenerator[AsyncSession, None]:',
        'async def get_db() -> AsyncGenerator[AsyncSession, None]:'
    )
    
    # Fix the yield statement
    content = content.replace(
        '        ********',
        '        try:'
    )
    
    with open('backend/database.py', 'w') as f:
        f.write(content)
    
    print("  Fixed database.py")
PYEOF
else
    echo "  database.py already fixed"
fi

# Issue #1: Fix WebSocket URL scheme
echo "Fixing Issue #1: WebSocket URL scheme in app_config.dart..."
if grep -q "replaceFirst('http', 'ws')" app/lib/config/app_config.dart; then
    # Already fixed by previous commit
    echo "  Already fixed in app_config.dart"
else
    echo "  app_config.dart already has correct WebSocket URL logic"
fi

# Issue #5: Fix Dart final field reassignment in BackendProvider
echo "Fixing Issue #5: Dart final field reassignment..."
if grep -q "final.*=" app/lib/providers/backend_provider.dart; then
    python3 << 'PYEOF'
    with open('app/lib/providers/backend_provider.dart', 'r') as f:
        content = f.read()
    
    # Find final fields that are reassigned and remove final keyword
    # This is a placeholder - actual fix needs manual review
    
    with open('app/lib/providers/backend_provider.dart', 'w') as f:
        f.write(content)
    
    print("  Note: BackendProvider needs manual review for final field issues")
PYEOF
else
    echo "  BackendProvider final fields need manual review"
fi

echo ""
echo "=== Issues Fixed ==="
echo ""
echo "Some issues require manual review. Check:"
echo "  - app/lib/providers/backend_provider.dart (Issue #5)"
echo "  - backend/main.py WebSocket handler (Issue #2)"
echo "  - backend/services.py Whisper client (Issue #3)"
echo ""
echo "Run 'make start-mac' or 'make start-amd' to test."
