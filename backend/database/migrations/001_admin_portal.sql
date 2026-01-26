-- Admin Portal: Connections and Tags
-- Migration for subscriber/subscription management
-- Run this in Supabase SQL Editor after schema.sql

-- ============================================
-- CONNECTION STATUS
-- ============================================
CREATE TYPE connection_status AS ENUM (
    'pending',    -- Request sent, awaiting approval
    'active',     -- Approved and active connection
    'paused',     -- Temporarily paused by either party
    'declined',   -- Request was declined
    'archived'    -- Connection ended/archived
);

-- ============================================
-- CONNECTIONS (Subscriber/Subscription relationships)
-- ============================================
-- A connection represents a one-way relationship:
-- subscriber_id subscribes TO owner_id
-- owner_id is the "professional" who manages this connection
CREATE TABLE connections (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    subscriber_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status connection_status NOT NULL DEFAULT 'pending',
    request_message TEXT,                    -- Optional message with subscription request
    status_changed_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    -- Prevent duplicate connections
    UNIQUE(owner_id, subscriber_id)
);

CREATE INDEX idx_connections_owner ON connections(owner_id);
CREATE INDEX idx_connections_subscriber ON connections(subscriber_id);
CREATE INDEX idx_connections_status ON connections(status);

-- ============================================
-- TAGS (for organizing subscribers)
-- ============================================
CREATE TABLE tags (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    color TEXT NOT NULL DEFAULT '#007AFF',   -- Hex color for display
    created_at TIMESTAMPTZ DEFAULT NOW(),

    -- Each user's tags must have unique names
    UNIQUE(owner_id, name)
);

CREATE INDEX idx_tags_owner ON tags(owner_id);

-- ============================================
-- CONNECTION_TAGS (many-to-many)
-- ============================================
CREATE TABLE connection_tags (
    connection_id UUID NOT NULL REFERENCES connections(id) ON DELETE CASCADE,
    tag_id UUID NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    assigned_at TIMESTAMPTZ DEFAULT NOW(),

    PRIMARY KEY (connection_id, tag_id)
);

CREATE INDEX idx_connection_tags_connection ON connection_tags(connection_id);
CREATE INDEX idx_connection_tags_tag ON connection_tags(tag_id);

-- ============================================
-- TRIGGERS
-- ============================================

-- Auto-update updated_at for connections
CREATE TRIGGER connections_updated_at
    BEFORE UPDATE ON connections
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================

ALTER TABLE connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE connection_tags ENABLE ROW LEVEL SECURITY;

-- Connections: viewable by owner or subscriber
CREATE POLICY "View own connections"
    ON connections FOR SELECT
    TO authenticated
    USING (owner_id = auth.uid() OR subscriber_id = auth.uid());

-- Connections: insertable by subscriber (requesting)
CREATE POLICY "Create subscription request"
    ON connections FOR INSERT
    TO authenticated
    WITH CHECK (subscriber_id = auth.uid());

-- Connections: updatable by owner (approve/decline/manage)
CREATE POLICY "Owner manages connections"
    ON connections FOR UPDATE
    TO authenticated
    USING (owner_id = auth.uid());

-- Tags: viewable/manageable only by owner
CREATE POLICY "View own tags"
    ON tags FOR SELECT
    TO authenticated
    USING (owner_id = auth.uid());

CREATE POLICY "Create own tags"
    ON tags FOR INSERT
    TO authenticated
    WITH CHECK (owner_id = auth.uid());

CREATE POLICY "Update own tags"
    ON tags FOR UPDATE
    TO authenticated
    USING (owner_id = auth.uid());

CREATE POLICY "Delete own tags"
    ON tags FOR DELETE
    TO authenticated
    USING (owner_id = auth.uid());

-- Connection tags: manageable by connection owner
CREATE POLICY "View connection tags"
    ON connection_tags FOR SELECT
    TO authenticated
    USING (
        connection_id IN (
            SELECT id FROM connections WHERE owner_id = auth.uid()
        )
    );

CREATE POLICY "Manage connection tags"
    ON connection_tags FOR ALL
    TO authenticated
    USING (
        connection_id IN (
            SELECT id FROM connections WHERE owner_id = auth.uid()
        )
    );
