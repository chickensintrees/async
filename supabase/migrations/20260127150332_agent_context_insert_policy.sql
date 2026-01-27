-- Migration: Enable INSERT on agent_context table
-- Allows session summaries and context to be stored for agents

-- Drop existing policy if it exists (idempotent)
DROP POLICY IF EXISTS "Agent context is insertable" ON agent_context;

-- Add insert policy for agent context
CREATE POLICY "Agent context is insertable"
    ON agent_context FOR INSERT
    TO anon, authenticated
    WITH CHECK (true);
