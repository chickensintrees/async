-- Async Database Schema
-- Designed for Supabase (Postgres) but kept portable
-- Run this in Supabase SQL Editor or via migrations

-- Enable UUID extension (Supabase has this by default)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- USERS
-- ============================================
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    github_handle TEXT UNIQUE,
    display_name TEXT NOT NULL,
    email TEXT UNIQUE,
    avatar_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for lookups
CREATE INDEX idx_users_github_handle ON users(github_handle);

-- ============================================
-- CONVERSATIONS
-- ============================================
CREATE TYPE conversation_mode AS ENUM ('anonymous', 'assisted', 'direct');

CREATE TABLE conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    mode conversation_mode NOT NULL DEFAULT 'assisted',
    title TEXT,  -- Optional display title
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- CONVERSATION PARTICIPANTS
-- Many-to-many relationship between users and conversations
-- ============================================
CREATE TABLE conversation_participants (
    conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    role TEXT DEFAULT 'member',  -- 'member', 'admin', etc.
    PRIMARY KEY (conversation_id, user_id)
);

CREATE INDEX idx_participants_user ON conversation_participants(user_id);
CREATE INDEX idx_participants_conversation ON conversation_participants(conversation_id);

-- ============================================
-- MESSAGES
-- ============================================
CREATE TABLE messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id UUID REFERENCES users(id) ON DELETE SET NULL,

    -- Content fields
    content_raw TEXT NOT NULL,           -- What the sender actually typed
    content_processed TEXT,              -- AI-transformed version (nullable)

    -- Metadata
    is_from_agent BOOLEAN DEFAULT FALSE, -- True if this is an AI-generated message
    agent_context JSONB,                 -- Any context the agent wants to store

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    processed_at TIMESTAMPTZ,            -- When AI processing completed

    -- For anonymous mode: who sees what
    -- NULL means everyone sees content_processed (or raw if no processing)
    raw_visible_to UUID[]                -- Array of user IDs who can see raw content
);

CREATE INDEX idx_messages_conversation ON messages(conversation_id);
CREATE INDEX idx_messages_sender ON messages(sender_id);
CREATE INDEX idx_messages_created ON messages(created_at DESC);

-- ============================================
-- MESSAGE READ STATUS
-- Track who has read which messages
-- ============================================
CREATE TABLE message_reads (
    message_id UUID REFERENCES messages(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    read_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (message_id, user_id)
);

CREATE INDEX idx_reads_user ON message_reads(user_id);

-- ============================================
-- HELPER FUNCTIONS
-- ============================================

-- Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER conversations_updated_at
    BEFORE UPDATE ON conversations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================
-- ROW LEVEL SECURITY (RLS)
-- Supabase uses RLS for access control
-- ============================================

-- Enable RLS on all tables
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversation_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE message_reads ENABLE ROW LEVEL SECURITY;

-- Policies (basic - refine based on auth strategy)
-- For now, allow authenticated users to read their own data

-- Users can read all users (for display names, avatars)
CREATE POLICY "Users are viewable by authenticated users"
    ON users FOR SELECT
    TO authenticated
    USING (true);

-- Users can update their own profile
CREATE POLICY "Users can update own profile"
    ON users FOR UPDATE
    TO authenticated
    USING (auth.uid() = id);

-- Participants can view conversations they're in
CREATE POLICY "View conversations you're in"
    ON conversations FOR SELECT
    TO authenticated
    USING (
        id IN (
            SELECT conversation_id FROM conversation_participants
            WHERE user_id = auth.uid()
        )
    );

-- Participants can view messages in their conversations
CREATE POLICY "View messages in your conversations"
    ON messages FOR SELECT
    TO authenticated
    USING (
        conversation_id IN (
            SELECT conversation_id FROM conversation_participants
            WHERE user_id = auth.uid()
        )
    );

-- Participants can insert messages in their conversations
CREATE POLICY "Send messages to your conversations"
    ON messages FOR INSERT
    TO authenticated
    WITH CHECK (
        conversation_id IN (
            SELECT conversation_id FROM conversation_participants
            WHERE user_id = auth.uid()
        )
    );

-- ============================================
-- REALTIME
-- Enable realtime for messages (Supabase feature)
-- ============================================
-- Run in Supabase dashboard: Database → Replication → Enable for messages table
