-- Migration: SMS Support for Group Chat
-- Enables Twilio SMS integration for Bill + Noah + STEF group chat
-- Run in Supabase SQL Editor

-- ============================================
-- ADD PHONE NUMBER TO USERS
-- ============================================
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone_number TEXT UNIQUE;

CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone_number);

-- ============================================
-- ADD MESSAGE SOURCE TRACKING
-- ============================================
-- Track where messages originate (sms, app, api)
ALTER TABLE messages ADD COLUMN IF NOT EXISTS source TEXT DEFAULT 'app';

-- ============================================
-- STEF (AI AGENT) USER
-- ============================================
-- Create a user record for STEF so it can be a conversation participant
INSERT INTO users (id, github_handle, display_name)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'stef-ai',
    'STEF'
) ON CONFLICT (github_handle) DO NOTHING;

-- ============================================
-- SMS GROUP CHAT CONVERSATION
-- ============================================
-- Create the dedicated SMS group chat conversation
INSERT INTO conversations (id, mode, title)
VALUES (
    '00000000-0000-0000-0000-000000000002',
    'assisted',
    'Async Dev Chat (SMS)'
) ON CONFLICT (id) DO NOTHING;

-- ============================================
-- WEBHOOK ACCESS POLICY
-- ============================================
-- Allow service role (used by Edge Functions) to insert messages
-- Drop existing policies first to avoid conflicts
DROP POLICY IF EXISTS "Service role can insert messages" ON messages;
DROP POLICY IF EXISTS "Service role can read messages" ON messages;
DROP POLICY IF EXISTS "Service role can manage users" ON users;
DROP POLICY IF EXISTS "Service role can manage participants" ON conversation_participants;

CREATE POLICY "Service role can insert messages"
    ON messages FOR INSERT
    TO service_role
    WITH CHECK (true);

CREATE POLICY "Service role can read messages"
    ON messages FOR SELECT
    TO service_role
    USING (true);

CREATE POLICY "Service role can manage users"
    ON users FOR ALL
    TO service_role
    USING (true);

CREATE POLICY "Service role can manage participants"
    ON conversation_participants FOR ALL
    TO service_role
    USING (true);

-- ============================================
-- HELPER: LOOKUP USER BY PHONE
-- ============================================
CREATE OR REPLACE FUNCTION get_or_create_user_by_phone(
    p_phone TEXT,
    p_display_name TEXT DEFAULT 'Unknown'
)
RETURNS UUID AS $$
DECLARE
    v_user_id UUID;
BEGIN
    -- Try to find existing user
    SELECT id INTO v_user_id FROM users WHERE phone_number = p_phone;

    -- Create if not found
    IF v_user_id IS NULL THEN
        INSERT INTO users (phone_number, display_name)
        VALUES (p_phone, p_display_name)
        RETURNING id INTO v_user_id;
    END IF;

    RETURN v_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
