-- Migration: 011_therapy_training.sql
-- Purpose: Add tables for therapist training feature
-- Date: 2026-01-29
-- Feature: Therapist agent training from session recordings

-- ============================================================
-- THERAPY SESSIONS TABLE
-- ============================================================
-- Stores uploaded therapy session recordings

CREATE TABLE IF NOT EXISTS therapy_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    therapist_id UUID REFERENCES users(id) ON DELETE CASCADE,
    patient_alias TEXT,                    -- "Patient A" (anonymized)

    -- Audio
    audio_url TEXT NOT NULL,
    audio_duration_seconds INTEGER,
    audio_format TEXT,                     -- "m4a", "mp3", "wav"

    -- Metadata
    session_date DATE,
    session_notes TEXT,

    -- Processing
    status TEXT DEFAULT 'uploaded',        -- uploaded, transcribing, extracting, complete, error
    error_message TEXT,

    -- Consent
    consent_obtained BOOLEAN DEFAULT FALSE,
    consent_date TIMESTAMPTZ,
    consent_method TEXT,                   -- "verbal", "signed", "in_app"

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for therapy_sessions
CREATE INDEX IF NOT EXISTS idx_therapy_sessions_therapist ON therapy_sessions(therapist_id);
CREATE INDEX IF NOT EXISTS idx_therapy_sessions_status ON therapy_sessions(status);
CREATE INDEX IF NOT EXISTS idx_therapy_sessions_patient ON therapy_sessions(therapist_id, patient_alias);

-- ============================================================
-- SESSION TRANSCRIPTS TABLE
-- ============================================================
-- Stores transcription results for therapy sessions

CREATE TABLE IF NOT EXISTS session_transcripts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID REFERENCES therapy_sessions(id) ON DELETE CASCADE,

    full_text TEXT NOT NULL,
    segments JSONB,                        -- [{speaker, start, end, text, confidence}]
    therapist_speaker_id TEXT,             -- Which speaker is the therapist

    whisper_model TEXT,
    processing_time_ms INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for transcript lookup
CREATE INDEX IF NOT EXISTS idx_session_transcripts_session ON session_transcripts(session_id);

-- ============================================================
-- PATIENT PROFILES TABLE (anonymized)
-- ============================================================
-- Stores anonymized patient profiles for training context

CREATE TABLE IF NOT EXISTS patient_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    therapist_id UUID REFERENCES users(id) ON DELETE CASCADE,
    alias TEXT NOT NULL,                   -- "Patient A"

    profile_data JSONB,                    -- {presenting_issues, progress, techniques_tried}
    session_count INTEGER DEFAULT 0,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for patient_profiles
CREATE INDEX IF NOT EXISTS idx_patient_profiles_therapist ON patient_profiles(therapist_id);
CREATE INDEX IF NOT EXISTS idx_patient_profiles_alias ON patient_profiles(therapist_id, alias);

-- ============================================================
-- THERAPIST PATTERNS TABLE
-- ============================================================
-- Stores extracted patterns from therapy sessions

CREATE TABLE IF NOT EXISTS therapist_patterns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    therapist_id UUID REFERENCES users(id) ON DELETE CASCADE,
    session_id UUID REFERENCES therapy_sessions(id),

    pattern_type TEXT NOT NULL,            -- "technique", "phrase", "response_style"
    category TEXT,                         -- "opening", "reflection", "challenge", "closing"
    title TEXT NOT NULL,
    content TEXT NOT NULL,

    confidence NUMERIC(3,2),
    occurrence_count INTEGER DEFAULT 1,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for therapist_patterns
CREATE INDEX IF NOT EXISTS idx_therapist_patterns_therapist ON therapist_patterns(therapist_id);
CREATE INDEX IF NOT EXISTS idx_therapist_patterns_session ON therapist_patterns(session_id);
CREATE INDEX IF NOT EXISTS idx_therapist_patterns_type ON therapist_patterns(pattern_type);

-- ============================================================
-- TRAINING DOCUMENTS TABLE
-- ============================================================
-- Stores non-session training content from therapist or patient

CREATE TABLE IF NOT EXISTS training_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    therapist_id UUID REFERENCES users(id) ON DELETE CASCADE,
    patient_profile_id UUID REFERENCES patient_profiles(id),  -- Optional: patient-specific

    -- Who contributed this
    author_type TEXT NOT NULL,             -- "therapist" or "patient"

    -- Content
    document_type TEXT NOT NULL,           -- "case_note", "treatment_plan", "approach", "self_description", "goal", "journal", "musing"
    title TEXT,
    content TEXT NOT NULL,

    -- Processing
    status TEXT DEFAULT 'pending',         -- pending, processed
    extracted_insights JSONB,              -- Patterns/context extracted from this doc

    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for training_documents
CREATE INDEX IF NOT EXISTS idx_training_docs_therapist ON training_documents(therapist_id);
CREATE INDEX IF NOT EXISTS idx_training_docs_patient ON training_documents(patient_profile_id);
CREATE INDEX IF NOT EXISTS idx_training_docs_author ON training_documents(author_type);
CREATE INDEX IF NOT EXISTS idx_training_docs_type ON training_documents(document_type);

-- ============================================================
-- EXTEND AGENT_CONFIGS FOR THERAPY TRAINING
-- ============================================================
-- Add fields for therapy-specific agent configuration

ALTER TABLE agent_configs
ADD COLUMN IF NOT EXISTS therapist_profile JSONB,
ADD COLUMN IF NOT EXISTS training_sessions UUID[];

-- Comment for documentation
COMMENT ON COLUMN agent_configs.therapist_profile IS 'JSONB containing therapist-specific configuration (style, approach, patient context)';
COMMENT ON COLUMN agent_configs.training_sessions IS 'Array of therapy_session UUIDs used to train this agent';

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================

-- Enable RLS
ALTER TABLE therapy_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE session_transcripts ENABLE ROW LEVEL SECURITY;
ALTER TABLE patient_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE therapist_patterns ENABLE ROW LEVEL SECURITY;
ALTER TABLE training_documents ENABLE ROW LEVEL SECURITY;

-- Therapy sessions: therapist only
CREATE POLICY "therapist_sessions_select" ON therapy_sessions
    FOR SELECT USING (therapist_id = auth.uid());

CREATE POLICY "therapist_sessions_insert" ON therapy_sessions
    FOR INSERT WITH CHECK (therapist_id = auth.uid());

CREATE POLICY "therapist_sessions_update" ON therapy_sessions
    FOR UPDATE USING (therapist_id = auth.uid());

CREATE POLICY "therapist_sessions_delete" ON therapy_sessions
    FOR DELETE USING (therapist_id = auth.uid());

-- Session transcripts: via session ownership
CREATE POLICY "session_transcripts_select" ON session_transcripts
    FOR SELECT USING (
        session_id IN (SELECT id FROM therapy_sessions WHERE therapist_id = auth.uid())
    );

CREATE POLICY "session_transcripts_insert" ON session_transcripts
    FOR INSERT WITH CHECK (
        session_id IN (SELECT id FROM therapy_sessions WHERE therapist_id = auth.uid())
    );

CREATE POLICY "session_transcripts_update" ON session_transcripts
    FOR UPDATE USING (
        session_id IN (SELECT id FROM therapy_sessions WHERE therapist_id = auth.uid())
    );

CREATE POLICY "session_transcripts_delete" ON session_transcripts
    FOR DELETE USING (
        session_id IN (SELECT id FROM therapy_sessions WHERE therapist_id = auth.uid())
    );

-- Patient profiles: therapist only
CREATE POLICY "patient_profiles_select" ON patient_profiles
    FOR SELECT USING (therapist_id = auth.uid());

CREATE POLICY "patient_profiles_insert" ON patient_profiles
    FOR INSERT WITH CHECK (therapist_id = auth.uid());

CREATE POLICY "patient_profiles_update" ON patient_profiles
    FOR UPDATE USING (therapist_id = auth.uid());

CREATE POLICY "patient_profiles_delete" ON patient_profiles
    FOR DELETE USING (therapist_id = auth.uid());

-- Therapist patterns: therapist only
CREATE POLICY "therapist_patterns_select" ON therapist_patterns
    FOR SELECT USING (therapist_id = auth.uid());

CREATE POLICY "therapist_patterns_insert" ON therapist_patterns
    FOR INSERT WITH CHECK (therapist_id = auth.uid());

CREATE POLICY "therapist_patterns_update" ON therapist_patterns
    FOR UPDATE USING (therapist_id = auth.uid());

CREATE POLICY "therapist_patterns_delete" ON therapist_patterns
    FOR DELETE USING (therapist_id = auth.uid());

-- Training documents: therapist only
CREATE POLICY "training_docs_select" ON training_documents
    FOR SELECT USING (therapist_id = auth.uid());

CREATE POLICY "training_docs_insert" ON training_documents
    FOR INSERT WITH CHECK (therapist_id = auth.uid());

CREATE POLICY "training_docs_update" ON training_documents
    FOR UPDATE USING (therapist_id = auth.uid());

CREATE POLICY "training_docs_delete" ON training_documents
    FOR DELETE USING (therapist_id = auth.uid());

-- ============================================================
-- VERIFICATION
-- ============================================================

DO $$
DECLARE
    table_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO table_count
    FROM information_schema.tables
    WHERE table_name IN ('therapy_sessions', 'session_transcripts', 'patient_profiles', 'therapist_patterns', 'training_documents');

    RAISE NOTICE 'Therapy training tables created: % of 5', table_count;
END $$;
