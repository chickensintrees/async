-- Migration: 013_simplify_therapy_local_only.sql
-- Purpose: Simplify therapy training to local-only processing
-- Date: 2026-01-30
--
-- ARCHITECTURE CHANGE:
-- Raw content (transcripts, documents) stays LOCAL on device
-- Only extracted patterns and agent config go to Supabase
-- This improves privacy and reduces storage costs

-- ============================================================
-- DROP RAW CONTENT TABLES (content stays local)
-- ============================================================

-- Drop dependent foreign keys first
ALTER TABLE therapist_patterns
DROP CONSTRAINT IF EXISTS therapist_patterns_session_id_fkey;

-- Drop training_documents (raw content stays local)
DROP TABLE IF EXISTS training_documents CASCADE;

-- Drop session_transcripts (raw content stays local)
DROP TABLE IF EXISTS session_transcripts CASCADE;

-- Drop therapy_sessions (raw content stays local)
DROP TABLE IF EXISTS therapy_sessions CASCADE;

-- Drop patient_profiles (can rebuild from patterns if needed)
DROP TABLE IF EXISTS patient_profiles CASCADE;

-- ============================================================
-- CLEAN UP THERAPIST_PATTERNS
-- ============================================================
-- Remove session_id column since we dropped therapy_sessions
ALTER TABLE therapist_patterns
DROP COLUMN IF EXISTS session_id;

-- Add source_hash to detect duplicate extractions from same content
ALTER TABLE therapist_patterns
ADD COLUMN IF NOT EXISTS source_hash TEXT;

COMMENT ON COLUMN therapist_patterns.source_hash IS 'Hash of source content to prevent duplicate pattern extraction';

-- ============================================================
-- CLEAN UP AGENT_CONFIGS
-- ============================================================
-- Remove training_sessions array since we dropped that table
ALTER TABLE agent_configs
DROP COLUMN IF EXISTS training_sessions;

-- Keep therapist_profile - this stores the generated system prompt
-- Add generated_prompt field for the actual prompt text
ALTER TABLE agent_configs
ADD COLUMN IF NOT EXISTS generated_prompt TEXT;

COMMENT ON COLUMN agent_configs.generated_prompt IS 'AI-generated system prompt built from therapist patterns';

-- ============================================================
-- UPDATE RLS POLICIES FOR THERAPIST_PATTERNS
-- ============================================================
-- Make policies more permissive for development

DROP POLICY IF EXISTS "therapist_patterns_select" ON therapist_patterns;
DROP POLICY IF EXISTS "therapist_patterns_insert" ON therapist_patterns;
DROP POLICY IF EXISTS "therapist_patterns_update" ON therapist_patterns;
DROP POLICY IF EXISTS "therapist_patterns_delete" ON therapist_patterns;

-- Permissive policies that validate therapist exists
CREATE POLICY "therapist_patterns_all" ON therapist_patterns
    FOR ALL USING (
        therapist_id IN (SELECT id FROM users)
    );

-- ============================================================
-- VERIFICATION
-- ============================================================

DO $$
DECLARE
    dropped_count INTEGER;
    remaining_count INTEGER;
BEGIN
    -- Check dropped tables
    SELECT COUNT(*) INTO dropped_count
    FROM information_schema.tables
    WHERE table_name IN ('therapy_sessions', 'session_transcripts', 'training_documents', 'patient_profiles')
    AND table_schema = 'public';

    -- Check remaining tables
    SELECT COUNT(*) INTO remaining_count
    FROM information_schema.tables
    WHERE table_name IN ('therapist_patterns', 'agent_configs')
    AND table_schema = 'public';

    RAISE NOTICE 'Dropped tables remaining: % (should be 0)', dropped_count;
    RAISE NOTICE 'Required tables present: % (should be 2)', remaining_count;
END $$;
