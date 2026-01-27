-- Migration 008: Agent Memory Indexes
-- Adds GIN index for efficient memory retrieval by participants

-- Add GIN index for participants array queries
-- This enables fast lookups like: WHERE participants @> ARRAY['agent-id']
CREATE INDEX IF NOT EXISTS idx_agent_context_participants
    ON agent_context USING GIN (participants);

-- Drop existing policies if they exist (safe to run multiple times)
DROP POLICY IF EXISTS "Agent context is insertable" ON agent_context;
DROP POLICY IF EXISTS "Agent context is updatable" ON agent_context;

-- Add insert policy for agent context (needed for memory storage)
CREATE POLICY "Agent context is insertable"
    ON agent_context FOR INSERT
    TO anon, authenticated
    WITH CHECK (true);

-- Add update policy for agent context
CREATE POLICY "Agent context is updatable"
    ON agent_context FOR UPDATE
    TO anon, authenticated
    USING (true);
