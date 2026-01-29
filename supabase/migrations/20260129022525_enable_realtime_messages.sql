-- Enable Realtime for messages table
-- This allows the Supabase Realtime subscription to receive INSERT events
-- Required for App STEF's autonomous @mention responses

ALTER PUBLICATION supabase_realtime ADD TABLE messages;
