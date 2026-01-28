-- Migration: 012_gamification.sql
-- Purpose: Gamification tables for cross-user leaderboard sync
-- Date: 2026-01-28

-- Player scores table (one row per player)
CREATE TABLE IF NOT EXISTS player_scores (
    id TEXT PRIMARY KEY,                    -- GitHub username
    display_name TEXT NOT NULL,
    total_score INTEGER DEFAULT 0,
    daily_score INTEGER DEFAULT 0,
    weekly_score INTEGER DEFAULT 0,
    streak INTEGER DEFAULT 0,
    penalties INTEGER DEFAULT 0,
    last_activity TIMESTAMPTZ,
    titles JSONB DEFAULT '[]',              -- Array of PlayerTitle objects
    daily_reset_date DATE,
    weekly_reset_date DATE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Score events table (audit trail of all scoring)
CREATE TABLE IF NOT EXISTS score_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id TEXT NOT NULL REFERENCES player_scores(id),
    timestamp TIMESTAMPTZ DEFAULT NOW(),
    event_type TEXT NOT NULL,               -- commit, issueClosed, prMerged, ciFailed, etc.
    points INTEGER NOT NULL,
    description TEXT NOT NULL,
    related_url TEXT,                       -- GitHub link
    related_issue_number INTEGER,           -- For issue-based events
    metadata JSONB                          -- Flexible extra data
);

-- Scored issues table (prevent double-counting closed issues)
CREATE TABLE IF NOT EXISTS scored_issues (
    issue_number INTEGER PRIMARY KEY,
    player_id TEXT NOT NULL REFERENCES player_scores(id),
    story_points INTEGER NOT NULL,
    gamification_points INTEGER NOT NULL,
    scored_at TIMESTAMPTZ DEFAULT NOW()
);

-- Game commentary table
CREATE TABLE IF NOT EXISTS game_commentary (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    timestamp TIMESTAMPTZ DEFAULT NOW(),
    trigger TEXT NOT NULL,
    content TEXT NOT NULL,
    target_user TEXT
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_score_events_player ON score_events(player_id);
CREATE INDEX IF NOT EXISTS idx_score_events_timestamp ON score_events(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_scored_issues_player ON scored_issues(player_id);

-- Enable RLS
ALTER TABLE player_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE score_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE scored_issues ENABLE ROW LEVEL SECURITY;
ALTER TABLE game_commentary ENABLE ROW LEVEL SECURITY;

-- Public read access for gamification data
DROP POLICY IF EXISTS "Gamification scores are public" ON player_scores;
CREATE POLICY "Gamification scores are public" ON player_scores FOR SELECT USING (true);

DROP POLICY IF EXISTS "Score events are public" ON score_events;
CREATE POLICY "Score events are public" ON score_events FOR SELECT USING (true);

DROP POLICY IF EXISTS "Scored issues are public" ON scored_issues;
CREATE POLICY "Scored issues are public" ON scored_issues FOR SELECT USING (true);

DROP POLICY IF EXISTS "Commentary is public" ON game_commentary;
CREATE POLICY "Commentary is public" ON game_commentary FOR SELECT USING (true);

-- Allow inserts/updates (service will handle auth)
DROP POLICY IF EXISTS "Allow insert player_scores" ON player_scores;
CREATE POLICY "Allow insert player_scores" ON player_scores FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "Allow update player_scores" ON player_scores;
CREATE POLICY "Allow update player_scores" ON player_scores FOR UPDATE USING (true);

DROP POLICY IF EXISTS "Allow insert score_events" ON score_events;
CREATE POLICY "Allow insert score_events" ON score_events FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "Allow insert scored_issues" ON scored_issues;
CREATE POLICY "Allow insert scored_issues" ON scored_issues FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "Allow insert commentary" ON game_commentary;
CREATE POLICY "Allow insert commentary" ON game_commentary FOR INSERT WITH CHECK (true);

-- Seed initial players
INSERT INTO player_scores (id, display_name, total_score, streak) VALUES
    ('chickensintrees', 'Bill', 0, 0),
    ('ginzatron', 'Noah', 0, 0)
ON CONFLICT (id) DO NOTHING;
