-- Migration: Add connections and tags tables for Admin Portal
-- Date: 2026-01-26
-- Description: Enables subscription/connection management with tagging

-- ============================================
-- CONNECTION STATUS ENUM
-- ============================================
CREATE TYPE connection_status AS ENUM ('pending', 'active', 'paused', 'declined', 'archived');

-- ============================================
-- CONNECTIONS
-- Represents a subscription relationship: subscriber wants access to owner's content
-- Owner controls approval, subscriber requests access
-- ============================================
CREATE TABLE connections (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_id UUID REFERENCES users(id) ON DELETE CASCADE,
    subscriber_id UUID REFERENCES users(id) ON DELETE CASCADE,
    status connection_status NOT NULL DEFAULT 'pending',
    request_message TEXT,
    status_changed_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(owner_id, subscriber_id)  -- Prevent duplicate connections
);

CREATE INDEX idx_connections_owner ON connections(owner_id);
CREATE INDEX idx_connections_subscriber ON connections(subscriber_id);
CREATE INDEX idx_connections_status ON connections(status);

-- Auto-update updated_at
CREATE TRIGGER connections_updated_at
    BEFORE UPDATE ON connections
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================
-- TAGS
-- User-defined labels for organizing connections
-- ============================================
CREATE TABLE tags (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_id UUID REFERENCES users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    color TEXT NOT NULL DEFAULT '#3B82F6',  -- Default blue
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(owner_id, name)  -- Tags unique per user
);

CREATE INDEX idx_tags_owner ON tags(owner_id);

-- ============================================
-- CONNECTION_TAGS (Junction Table)
-- Many-to-many between connections and tags
-- ============================================
CREATE TABLE connection_tags (
    connection_id UUID REFERENCES connections(id) ON DELETE CASCADE,
    tag_id UUID REFERENCES tags(id) ON DELETE CASCADE,
    assigned_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (connection_id, tag_id)
);

CREATE INDEX idx_connection_tags_connection ON connection_tags(connection_id);
CREATE INDEX idx_connection_tags_tag ON connection_tags(tag_id);

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================
ALTER TABLE connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE connection_tags ENABLE ROW LEVEL SECURITY;

-- Connections: owners and subscribers can see their own connections
CREATE POLICY "View own connections"
    ON connections FOR SELECT
    TO authenticated
    USING (owner_id = auth.uid() OR subscriber_id = auth.uid());

-- Connections: anyone can create (request) a connection
CREATE POLICY "Create connection requests"
    ON connections FOR INSERT
    TO authenticated
    WITH CHECK (subscriber_id = auth.uid());

-- Connections: owners can update status
CREATE POLICY "Owners can update connection status"
    ON connections FOR UPDATE
    TO authenticated
    USING (owner_id = auth.uid());

-- Connections: either party can delete
CREATE POLICY "Delete own connections"
    ON connections FOR DELETE
    TO authenticated
    USING (owner_id = auth.uid() OR subscriber_id = auth.uid());

-- Tags: users can manage their own tags
CREATE POLICY "Manage own tags"
    ON tags FOR ALL
    TO authenticated
    USING (owner_id = auth.uid());

-- Connection tags: connection owners can manage
CREATE POLICY "Manage connection tags"
    ON connection_tags FOR ALL
    TO authenticated
    USING (
        connection_id IN (
            SELECT id FROM connections WHERE owner_id = auth.uid()
        )
    );

-- ============================================
-- ANON KEY ACCESS (for development)
-- Allow anon key to read/write for testing
-- ============================================
CREATE POLICY "Anon read connections" ON connections FOR SELECT TO anon USING (true);
CREATE POLICY "Anon insert connections" ON connections FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "Anon update connections" ON connections FOR UPDATE TO anon USING (true);
CREATE POLICY "Anon delete connections" ON connections FOR DELETE TO anon USING (true);

CREATE POLICY "Anon read tags" ON tags FOR SELECT TO anon USING (true);
CREATE POLICY "Anon insert tags" ON tags FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "Anon update tags" ON tags FOR UPDATE TO anon USING (true);
CREATE POLICY "Anon delete tags" ON tags FOR DELETE TO anon USING (true);

CREATE POLICY "Anon read connection_tags" ON connection_tags FOR SELECT TO anon USING (true);
CREATE POLICY "Anon insert connection_tags" ON connection_tags FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "Anon delete connection_tags" ON connection_tags FOR DELETE TO anon USING (true);
