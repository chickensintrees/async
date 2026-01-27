-- Migration: Fix agent_context RLS policies
-- Ensures both anon and authenticated can read AND insert

-- Drop ALL existing policies on agent_context
DROP POLICY IF EXISTS "Agent context is readable" ON agent_context;
DROP POLICY IF EXISTS "Agent context is insertable" ON agent_context;
DROP POLICY IF EXISTS "Agent context is updatable" ON agent_context;

-- Recreate READ policy for both anon and authenticated
CREATE POLICY "Agent context is readable"
    ON agent_context FOR SELECT
    TO anon, authenticated
    USING (true);

-- Create INSERT policy for both anon and authenticated
CREATE POLICY "Agent context is insertable"
    ON agent_context FOR INSERT
    TO anon, authenticated
    WITH CHECK (true);

-- Create UPDATE policy for both anon and authenticated
CREATE POLICY "Agent context is updatable"
    ON agent_context FOR UPDATE
    TO anon, authenticated
    USING (true);
