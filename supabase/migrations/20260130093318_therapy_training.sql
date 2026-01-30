-- Migration: Therapy Training Tables
-- Purpose: Add tables for therapist agent training feature
-- Date: 2026-01-30

-- ============================================================
-- THERAPY SESSIONS TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS therapy_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    therapist_id UUID REFERENCES users(id) ON DELETE CASCADE,
    patient_alias TEXT,

    audio_url TEXT NOT NULL,
    audio_duration_seconds INTEGER,
    audio_format TEXT,

    session_date DATE,
    session_notes TEXT,

    status TEXT DEFAULT 'uploaded',
    error_message TEXT,

    consent_obtained BOOLEAN DEFAULT FALSE,
    consent_date TIMESTAMPTZ,
    consent_method TEXT,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_therapy_sessions_therapist ON therapy_sessions(therapist_id);
CREATE INDEX IF NOT EXISTS idx_therapy_sessions_status ON therapy_sessions(status);

-- ============================================================
-- SESSION TRANSCRIPTS TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS session_transcripts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID REFERENCES therapy_sessions(id) ON DELETE CASCADE,

    full_text TEXT NOT NULL,
    segments JSONB,
    therapist_speaker_id TEXT,

    whisper_model TEXT,
    processing_time_ms INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_session_transcripts_session ON session_transcripts(session_id);

-- ============================================================
-- PATIENT PROFILES TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS patient_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    therapist_id UUID REFERENCES users(id) ON DELETE CASCADE,
    alias TEXT NOT NULL,

    profile_data JSONB,
    session_count INTEGER DEFAULT 0,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_patient_profiles_therapist ON patient_profiles(therapist_id);

-- ============================================================
-- THERAPIST PATTERNS TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS therapist_patterns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    therapist_id UUID REFERENCES users(id) ON DELETE CASCADE,
    session_id UUID REFERENCES therapy_sessions(id),

    pattern_type TEXT NOT NULL,
    category TEXT,
    title TEXT NOT NULL,
    content TEXT NOT NULL,

    confidence NUMERIC(3,2),
    occurrence_count INTEGER DEFAULT 1,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_therapist_patterns_therapist ON therapist_patterns(therapist_id);
CREATE INDEX IF NOT EXISTS idx_therapist_patterns_session ON therapist_patterns(session_id);

-- ============================================================
-- TRAINING DOCUMENTS TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS training_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    therapist_id UUID REFERENCES users(id) ON DELETE CASCADE,
    patient_profile_id UUID REFERENCES patient_profiles(id),

    author_type TEXT NOT NULL,
    document_type TEXT NOT NULL,
    title TEXT,
    content TEXT NOT NULL,

    status TEXT DEFAULT 'pending',
    extracted_insights JSONB,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_training_docs_therapist ON training_documents(therapist_id);
CREATE INDEX IF NOT EXISTS idx_training_docs_patient ON training_documents(patient_profile_id);

-- ============================================================
-- EXTEND AGENT_CONFIGS
-- ============================================================

ALTER TABLE agent_configs
ADD COLUMN IF NOT EXISTS therapist_profile JSONB,
ADD COLUMN IF NOT EXISTS training_sessions UUID[];

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE therapy_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE session_transcripts ENABLE ROW LEVEL SECURITY;
ALTER TABLE patient_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE therapist_patterns ENABLE ROW LEVEL SECURITY;
ALTER TABLE training_documents ENABLE ROW LEVEL SECURITY;

-- Therapy sessions policies
CREATE POLICY "therapist_sessions_all" ON therapy_sessions
    FOR ALL USING (therapist_id = auth.uid());

-- Session transcripts policies
CREATE POLICY "session_transcripts_all" ON session_transcripts
    FOR ALL USING (
        session_id IN (SELECT id FROM therapy_sessions WHERE therapist_id = auth.uid())
    );

-- Patient profiles policies
CREATE POLICY "patient_profiles_all" ON patient_profiles
    FOR ALL USING (therapist_id = auth.uid());

-- Therapist patterns policies
CREATE POLICY "therapist_patterns_all" ON therapist_patterns
    FOR ALL USING (therapist_id = auth.uid());

-- Training documents policies
CREATE POLICY "training_docs_all" ON training_documents
    FOR ALL USING (therapist_id = auth.uid());
