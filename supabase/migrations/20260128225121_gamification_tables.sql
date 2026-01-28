-- Gamification tables for cross-user leaderboard sync

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
    titles JSONB DEFAULT '[]',
    daily_reset_date DATE,
    weekly_reset_date DATE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Score events table (audit trail)
CREATE TABLE IF NOT EXISTS score_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id TEXT NOT NULL REFERENCES player_scores(id),
    timestamp TIMESTAMPTZ DEFAULT NOW(),
    event_type TEXT NOT NULL,
    points INTEGER NOT NULL,
    description TEXT NOT NULL,
    related_url TEXT,
    related_issue_number INTEGER,
    metadata JSONB
);

-- Scored issues (prevent double-counting)
CREATE TABLE IF NOT EXISTS scored_issues (
    issue_number INTEGER PRIMARY KEY,
    player_id TEXT NOT NULL REFERENCES player_scores(id),
    story_points INTEGER NOT NULL,
    gamification_points INTEGER NOT NULL,
    scored_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_score_events_player ON score_events(player_id);
CREATE INDEX IF NOT EXISTS idx_score_events_timestamp ON score_events(timestamp DESC);

-- Enable RLS
ALTER TABLE player_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE score_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE scored_issues ENABLE ROW LEVEL SECURITY;

-- Public read access
CREATE POLICY "player_scores_select" ON player_scores FOR SELECT USING (true);
CREATE POLICY "score_events_select" ON score_events FOR SELECT USING (true);
CREATE POLICY "scored_issues_select" ON scored_issues FOR SELECT USING (true);

-- Allow inserts/updates
CREATE POLICY "player_scores_insert" ON player_scores FOR INSERT WITH CHECK (true);
CREATE POLICY "player_scores_update" ON player_scores FOR UPDATE USING (true);
CREATE POLICY "score_events_insert" ON score_events FOR INSERT WITH CHECK (true);
CREATE POLICY "scored_issues_insert" ON scored_issues FOR INSERT WITH CHECK (true);

-- Seed players
INSERT INTO player_scores (id, display_name) VALUES
    ('chickensintrees', 'Bill'),
    ('ginzatron', 'Noah')
ON CONFLICT (id) DO NOTHING;
