-- Migration: Add attachments column to messages
-- Purpose: Support image and file attachments on messages
-- Date: 2026-01-27

-- Add JSONB column for attachments
ALTER TABLE messages
ADD COLUMN IF NOT EXISTS attachments JSONB DEFAULT NULL;

-- Add index for querying messages with attachments
CREATE INDEX IF NOT EXISTS idx_messages_has_attachments
ON messages ((attachments IS NOT NULL));

-- Comment for documentation
COMMENT ON COLUMN messages.attachments IS 'JSONB array of MessageAttachment objects containing image/file metadata and URLs';
