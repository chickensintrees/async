-- Migration: Add attachments column to messages (minimal)
-- Date: 2026-01-27
-- Just the column, no RLS policies

ALTER TABLE messages ADD COLUMN IF NOT EXISTS attachments JSONB DEFAULT NULL;
