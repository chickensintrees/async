-- Migration: 009_conversation_privacy.sql
-- Purpose: Add privacy flag for cross-conversation agent memory
-- Date: 2026-01-27

-- Add is_private column (defaults to false - agents can access)
-- When true, agents cannot access this conversation from other conversations
ALTER TABLE conversations ADD COLUMN IF NOT EXISTS is_private BOOLEAN DEFAULT FALSE;

-- Partial index for efficient filtering (only indexes private conversations)
CREATE INDEX IF NOT EXISTS idx_conversations_is_private
ON conversations(is_private) WHERE is_private = TRUE;

-- Comment for documentation
COMMENT ON COLUMN conversations.is_private IS
    'When true, agents cannot access this conversation from other conversations. Human-only conversations remain private regardless of this flag.';
