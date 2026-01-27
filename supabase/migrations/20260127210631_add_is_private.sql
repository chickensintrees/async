-- Add is_private column to conversations table
-- When true, agents can't access conversation content from other conversations

ALTER TABLE conversations ADD COLUMN IF NOT EXISTS is_private BOOLEAN DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_conversations_is_private
ON conversations(is_private) WHERE is_private = TRUE;
