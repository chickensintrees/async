-- Migration: 006_agent_config_extended.sql
-- Purpose: Extend agent_configs for in-app agent management
-- Date: 2026-01-26
-- Issue: #20 Autonomous AI Agents System

-- ============================================================
-- EXTEND AGENT_CONFIGS TABLE
-- ============================================================

-- Model selection (claude-sonnet-4-20250514, claude-opus-4-5-20251101, etc.)
ALTER TABLE agent_configs
ADD COLUMN IF NOT EXISTS model TEXT DEFAULT 'claude-sonnet-4-20250514';

-- Temperature for response generation (0.0 - 1.0)
ALTER TABLE agent_configs
ADD COLUMN IF NOT EXISTS temperature NUMERIC(3,2) DEFAULT 0.7;

-- Knowledge base (JSONB for flexible document/context storage)
-- Example: {"documents": ["doc1.txt"], "context": "Additional context...", "examples": [...]}
ALTER TABLE agent_configs
ADD COLUMN IF NOT EXISTS knowledge_base JSONB;

-- Visibility: public agents available to all users, private only to creator
ALTER TABLE agent_configs
ADD COLUMN IF NOT EXISTS is_public BOOLEAN DEFAULT TRUE;

-- Creator tracking (who made this agent)
ALTER TABLE agent_configs
ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES users(id);

-- Description for agent directory listing
ALTER TABLE agent_configs
ADD COLUMN IF NOT EXISTS description TEXT;

-- Avatar URL for custom agent appearance
ALTER TABLE agent_configs
ADD COLUMN IF NOT EXISTS avatar_url TEXT;

-- ============================================================
-- INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_agent_configs_is_public ON agent_configs(is_public);
CREATE INDEX IF NOT EXISTS idx_agent_configs_created_by ON agent_configs(created_by);

-- ============================================================
-- UPDATE EXISTING AGENTS
-- ============================================================

-- Set STEF as public system agent
UPDATE agent_configs
SET is_public = TRUE,
    description = 'Built-in AI assistant for the Async messaging app. Helpful, technical, with a dry sense of humor.',
    model = 'claude-sonnet-4-20250514',
    temperature = 0.7
WHERE user_id = '00000000-0000-0000-0000-000000000001';

-- Set Greg as public character agent
UPDATE agent_configs
SET is_public = TRUE,
    description = 'A confused but friendly guy who somehow received a mysterious device. Loves his cat Mr. Whiskers.',
    model = 'claude-sonnet-4-20250514',
    temperature = 0.9
WHERE user_id = '00000000-0000-0000-0000-000000000002';

-- ============================================================
-- VERIFICATION
-- ============================================================

DO $$
DECLARE
    col_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO col_count
    FROM information_schema.columns
    WHERE table_name = 'agent_configs'
    AND column_name IN ('model', 'temperature', 'knowledge_base', 'is_public', 'created_by', 'description', 'avatar_url');

    RAISE NOTICE 'New columns added: %', col_count;
END $$;

-- Show updated agent configs
SELECT u.display_name, ac.model, ac.temperature, ac.is_public, ac.description
FROM users u
JOIN agent_configs ac ON u.id = ac.user_id;
