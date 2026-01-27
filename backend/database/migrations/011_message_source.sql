-- Migration: Add source column to messages table
-- Tracks where messages originated: app, terminal, sms, web

ALTER TABLE messages
ADD COLUMN IF NOT EXISTS source TEXT DEFAULT 'app';

COMMENT ON COLUMN messages.source IS
  'Origin of message: app (SwiftUI), terminal (CLI), sms (Twilio), web (future)';

-- Create index for filtering by source
CREATE INDEX IF NOT EXISTS idx_messages_source ON messages(source);

-- Backfill existing messages (assume they came from the app)
UPDATE messages SET source = 'app' WHERE source IS NULL;
