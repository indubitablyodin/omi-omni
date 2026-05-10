-- Omi Omni Database Initialization Script
-- This script runs when PostgreSQL container starts for the first time

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create default user
INSERT INTO users (username, email, created_at, updated_at)
VALUES ('default', 'default@omi-omni.local', NOW(), NOW())
ON CONFLICT (username) DO NOTHING;

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_conversations_user_id ON conversations(user_id);
CREATE INDEX IF NOT EXISTS idx_conversations_status ON conversations(status);
CREATE INDEX IF NOT EXISTS idx_conversations_created_at ON conversations(created_at);
CREATE INDEX IF NOT EXISTS idx_memories_user_id ON memories(user_id);
CREATE INDEX IF NOT EXISTS idx_memories_conversation_id ON memories(conversation_id);
CREATE INDEX IF NOT EXISTS idx_memories_created_at ON memories(created_at);
CREATE INDEX IF NOT EXISTS idx_conversation_segments_conversation_id ON conversation_segments(conversation_id);
CREATE INDEX IF NOT EXISTS idx_devices_user_id ON devices(user_id);
CREATE INDEX IF NOT EXISTS idx_recordings_user_id ON recordings(user_id);
CREATE INDEX IF NOT EXISTS idx_recordings_device_id ON recordings(device_id);

-- Create function for generating UUIDs
CREATE OR REPLACE FUNCTION generate_uuid()
RETURNS UUID AS $$
BEGIN
    RETURN uuid_generate_v4();
END;
$$ LANGUAGE plpgsql;

-- Create trigger for auto-updating updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply trigger to users table
DROP TRIGGER IF EXISTS update_users_updated_at ON users;
CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Create materialized view for statistics (optional)
CREATE MATERIALIZED VIEW IF NOT EXISTS stats_summary AS
SELECT 
    COUNT(*) as total_conversations,
    COUNT(*) FILTER (WHERE status = 'completed') as completed_conversations,
    COUNT(*) FILTER (WHERE status = 'processing') as processing_conversations,
    COUNT(DISTINCT user_id) as total_users
FROM conversations;

-- Create function to refresh stats
CREATE OR REPLACE FUNCTION refresh_stats()
RETURNS VOID AS $$
BEGIN
    REFRESH MATERIALIZED VIEW stats_summary;
END;
$$ LANGUAGE plpgsql;

-- Set up comments on tables
COMMENT ON TABLE users IS 'User accounts for Omi Omni';
COMMENT ON TABLE conversations IS 'Transcribed conversations from Omi device';
COMMENT ON TABLE conversation_segments IS 'Individual segments of conversations';
COMMENT ON TABLE memories IS 'Extracted memories for semantic search';
COMMENT ON TABLE devices IS 'Registered Omi devices';
COMMENT ON TABLE recordings IS 'Local recordings from Omi devices';

-- Log initialization
DO $$
BEGIN
    RAISE NOTICE 'Omi Omni database initialized successfully';
END $$;
