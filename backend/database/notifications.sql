-- Notification rate limiting and preferences
-- Run this in Supabase SQL Editor

-- Track notification sends for rate limiting
CREATE TABLE IF NOT EXISTS notification_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    notification_type TEXT NOT NULL DEFAULT 'sms',
    sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    message_preview TEXT,
    phone_number TEXT
);

-- Index for quick rate limit lookups
CREATE INDEX IF NOT EXISTS idx_notification_log_user_sent
ON notification_log(user_id, sent_at DESC);

-- User notification preferences
CREATE TABLE IF NOT EXISTS notification_preferences (
    user_id UUID PRIMARY KEY REFERENCES users(id),
    sms_enabled BOOLEAN DEFAULT true,
    phone_number TEXT,
    rate_limit_seconds INTEGER DEFAULT 60,  -- minimum seconds between notifications
    quiet_hours_start TIME,  -- e.g., '22:00' for 10pm
    quiet_hours_end TIME,    -- e.g., '08:00' for 8am
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE notification_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_preferences ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Users can view own notification log" ON notification_log
    FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Service can insert notifications" ON notification_log
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Users can manage own preferences" ON notification_preferences
    FOR ALL USING (user_id = auth.uid());

CREATE POLICY "Service can read preferences" ON notification_preferences
    FOR SELECT USING (true);

-- Function to check if we can send notification (rate limiting)
CREATE OR REPLACE FUNCTION can_send_notification(p_user_id UUID, p_rate_limit_seconds INTEGER DEFAULT 60)
RETURNS BOOLEAN AS $$
DECLARE
    last_sent TIMESTAMPTZ;
BEGIN
    SELECT sent_at INTO last_sent
    FROM notification_log
    WHERE user_id = p_user_id
    ORDER BY sent_at DESC
    LIMIT 1;

    IF last_sent IS NULL THEN
        RETURN true;
    END IF;

    RETURN (NOW() - last_sent) > (p_rate_limit_seconds || ' seconds')::INTERVAL;
END;
$$ LANGUAGE plpgsql;

-- Insert Noah's notification preferences
-- First we need his user_id, so this is a helper to set it up
DO $$
DECLARE
    noah_id UUID;
BEGIN
    SELECT id INTO noah_id FROM users WHERE github_handle = 'ginzatron';

    IF noah_id IS NOT NULL THEN
        INSERT INTO notification_preferences (user_id, phone_number, sms_enabled, rate_limit_seconds)
        VALUES (noah_id, '+14125123593', true, 60)
        ON CONFLICT (user_id) DO UPDATE SET
            phone_number = '+14125123593',
            sms_enabled = true;
    END IF;
END $$;
