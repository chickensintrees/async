-- Migration: Add image attachments support
-- Date: 2026-01-27
-- Author: STEF (Image Input Feature - Phase 1 MVP)

-- Add attachments column to messages table
-- Stores array of attachment objects as JSONB
ALTER TABLE messages ADD COLUMN IF NOT EXISTS attachments JSONB DEFAULT '[]';

-- Create storage bucket for message attachments
-- Using public bucket since authenticated users will have RLS anyway
INSERT INTO storage.buckets (id, name, public)
VALUES ('message-attachments', 'message-attachments', true)
ON CONFLICT (id) DO NOTHING;

-- RLS Policy: Users can upload to conversations they participate in
-- Path format: {conversation_id}/{filename}
CREATE POLICY "Users can upload to their conversations"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'message-attachments' AND
    EXISTS (
        SELECT 1 FROM conversation_participants cp
        WHERE cp.conversation_id = (storage.foldername(name))[1]::uuid
        AND cp.user_id = auth.uid()
    )
);

-- RLS Policy: Authenticated users can read attachments
-- Public within the app since messages are already protected by RLS
CREATE POLICY "Authenticated users can read attachments"
ON storage.objects FOR SELECT
TO authenticated
USING (bucket_id = 'message-attachments');

-- RLS Policy: Users can delete their own uploads
-- Useful for removing failed uploads or editing messages
CREATE POLICY "Users can delete their uploads"
ON storage.objects FOR DELETE
TO authenticated
USING (
    bucket_id = 'message-attachments' AND
    owner_id = auth.uid()
);

-- Index for efficient attachment queries (optional but good for future)
CREATE INDEX IF NOT EXISTS idx_messages_attachments
ON messages USING gin (attachments)
WHERE attachments != '[]'::jsonb;
