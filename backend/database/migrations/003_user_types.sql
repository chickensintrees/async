-- Migration: 003_user_types.sql
-- Purpose: Add user_type to distinguish humans from AI agents
-- Date: 2026-01-26

-- Add user_type column (human vs agent)
-- Defaults to 'human' for all existing users
ALTER TABLE users ADD COLUMN IF NOT EXISTS user_type TEXT NOT NULL DEFAULT 'human';

-- Add agent-specific metadata (nullable for humans)
-- Example: {"provider": "anthropic", "model": "claude-3", "capabilities": ["mediation"], "is_system": true}
ALTER TABLE users ADD COLUMN IF NOT EXISTS agent_metadata JSONB;

-- Index for efficient agent lookups
CREATE INDEX IF NOT EXISTS idx_users_user_type ON users(user_type);

-- Constraint for valid user types (only if not exists)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'check_user_type'
    ) THEN
        ALTER TABLE users ADD CONSTRAINT check_user_type CHECK (user_type IN ('human', 'agent'));
    END IF;
END $$;

-- Update STEF to be an agent
UPDATE users
SET user_type = 'agent',
    agent_metadata = jsonb_build_object(
        'provider', 'anthropic',
        'model', 'claude-3',
        'capabilities', ARRAY['mediation', 'summarization', 'context-aware'],
        'is_system', true
    )
WHERE id = '00000000-0000-0000-0000-000000000001';

-- Verify migration
DO $$
DECLARE
    stef_type TEXT;
BEGIN
    SELECT user_type INTO stef_type FROM users WHERE id = '00000000-0000-0000-0000-000000000001';
    IF stef_type IS NULL OR stef_type != 'agent' THEN
        RAISE WARNING 'STEF user not found or not updated to agent type';
    END IF;
END $$;
