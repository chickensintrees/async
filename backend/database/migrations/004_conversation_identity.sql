-- Migration: 004_conversation_identity.sql
-- Purpose: Add conversation identity fields for proper room-first model
-- Date: 2026-01-26
-- Issue: #21 Conversation Identity + Draft Semantics

-- ============================================================
-- CONVERSATIONS TABLE CHANGES
-- ============================================================

-- Add kind column to distinguish conversation types
-- Values: 'direct_1to1', 'direct_group', 'channel', 'system'
ALTER TABLE conversations ADD COLUMN IF NOT EXISTS kind TEXT NOT NULL DEFAULT 'direct_group';

-- Add topic for disambiguation when multiple conversations exist with same people
ALTER TABLE conversations ADD COLUMN IF NOT EXISTS topic TEXT;

-- Add last_message_at for proper sorting (conversations should sort by activity, not creation)
ALTER TABLE conversations ADD COLUMN IF NOT EXISTS last_message_at TIMESTAMPTZ;

-- Add canonical_key for 1:1 conversation reuse
-- Format: 'dm:{minUserId}:{maxUserId}:{mode}'
-- This ensures "Message STEF" always goes to the same conversation
ALTER TABLE conversations ADD COLUMN IF NOT EXISTS canonical_key TEXT;

-- Constraint for valid kind values
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'check_conversation_kind'
    ) THEN
        ALTER TABLE conversations ADD CONSTRAINT check_conversation_kind
        CHECK (kind IN ('direct_1to1', 'direct_group', 'channel', 'system'));
    END IF;
END $$;

-- Unique index on canonical_key for 1:1 reuse (only where not null)
CREATE UNIQUE INDEX IF NOT EXISTS idx_conversations_canonical_key
ON conversations(canonical_key) WHERE canonical_key IS NOT NULL;

-- Index for sorting by activity
CREATE INDEX IF NOT EXISTS idx_conversations_last_message_at
ON conversations(last_message_at DESC NULLS LAST);

-- ============================================================
-- CONVERSATION_PARTICIPANTS TABLE CHANGES (per-user state)
-- ============================================================

-- Per-user mute state
ALTER TABLE conversation_participants ADD COLUMN IF NOT EXISTS is_muted BOOLEAN DEFAULT FALSE;

-- Per-user archive state (not global archive)
ALTER TABLE conversation_participants ADD COLUMN IF NOT EXISTS is_archived BOOLEAN DEFAULT FALSE;

-- Last read message cursor (for unread counts)
ALTER TABLE conversation_participants ADD COLUMN IF NOT EXISTS last_read_message_id UUID;

-- Add FK constraint for last_read_message_id if not exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'fk_last_read_message'
    ) THEN
        ALTER TABLE conversation_participants
        ADD CONSTRAINT fk_last_read_message
        FOREIGN KEY (last_read_message_id) REFERENCES messages(id) ON DELETE SET NULL;
    END IF;
END $$;

-- ============================================================
-- BACKFILL EXISTING DATA
-- ============================================================

-- Set kind based on participant count
-- Note: This is approximate - 2 participants = 1:1, more = group
UPDATE conversations c
SET kind = CASE
    WHEN (SELECT COUNT(*) FROM conversation_participants WHERE conversation_id = c.id) = 2
    THEN 'direct_1to1'
    ELSE 'direct_group'
END
WHERE kind = 'direct_group';  -- Only update defaults

-- Set last_message_at from most recent message
UPDATE conversations c
SET last_message_at = (
    SELECT MAX(created_at)
    FROM messages m
    WHERE m.conversation_id = c.id
)
WHERE last_message_at IS NULL;

-- Generate canonical keys for existing 1:1 conversations
-- This uses a subquery to get the two participant IDs and orders them
UPDATE conversations c
SET canonical_key = (
    SELECT 'dm:' ||
        LEAST(p1.user_id::text, p2.user_id::text) || ':' ||
        GREATEST(p1.user_id::text, p2.user_id::text) || ':' ||
        c.mode
    FROM conversation_participants p1
    JOIN conversation_participants p2 ON p1.conversation_id = p2.conversation_id AND p1.user_id < p2.user_id
    WHERE p1.conversation_id = c.id
    LIMIT 1
)
WHERE kind = 'direct_1to1' AND canonical_key IS NULL;

-- ============================================================
-- TRIGGER: Auto-update last_message_at on new messages
-- ============================================================

CREATE OR REPLACE FUNCTION update_conversation_last_message_at()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE conversations
    SET last_message_at = NEW.created_at
    WHERE id = NEW.conversation_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_last_message_at ON messages;
CREATE TRIGGER trigger_update_last_message_at
AFTER INSERT ON messages
FOR EACH ROW
EXECUTE FUNCTION update_conversation_last_message_at();

-- ============================================================
-- VERIFICATION
-- ============================================================

DO $$
DECLARE
    conv_count INTEGER;
    with_kind INTEGER;
    with_last_msg INTEGER;
BEGIN
    SELECT COUNT(*) INTO conv_count FROM conversations;
    SELECT COUNT(*) INTO with_kind FROM conversations WHERE kind IS NOT NULL;
    SELECT COUNT(*) INTO with_last_msg FROM conversations WHERE last_message_at IS NOT NULL OR
        NOT EXISTS (SELECT 1 FROM messages WHERE conversation_id = conversations.id);

    RAISE NOTICE 'Migration 004 complete:';
    RAISE NOTICE '  Total conversations: %', conv_count;
    RAISE NOTICE '  With kind set: %', with_kind;
    RAISE NOTICE '  With last_message_at: %', with_last_msg;
END $$;
