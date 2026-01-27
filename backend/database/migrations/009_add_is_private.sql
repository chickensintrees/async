-- Migration: 009_add_is_private.sql
-- Purpose: Add is_private column to conversations table
-- Date: 2026-01-27
-- Issue: Missing column causing conversation creation to fail

-- Add is_private column (defaults to false)
-- When true, agents can't access conversation content from other conversations
ALTER TABLE conversations ADD COLUMN IF NOT EXISTS is_private BOOLEAN DEFAULT FALSE;

-- Index for filtering private conversations
CREATE INDEX IF NOT EXISTS idx_conversations_is_private
ON conversations(is_private) WHERE is_private = TRUE;

-- Verification
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'conversations' AND column_name = 'is_private'
    ) THEN
        RAISE NOTICE 'Migration 009 complete: is_private column added';
    ELSE
        RAISE EXCEPTION 'Migration 009 FAILED: is_private column not found';
    END IF;
END $$;
