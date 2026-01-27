-- =====================================================
-- SMS NOTIFICATIONS SETUP - Run this in Supabase SQL Editor
-- https://supabase.com/dashboard/project/ujokdwgpwruyiuioseir/sql
-- =====================================================

-- 1. Create notification tables
CREATE TABLE IF NOT EXISTS notification_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    notification_type TEXT NOT NULL DEFAULT 'sms',
    sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    message_preview TEXT,
    phone_number TEXT
);

CREATE INDEX IF NOT EXISTS idx_notification_log_user_sent
ON notification_log(user_id, sent_at DESC);

CREATE TABLE IF NOT EXISTS notification_preferences (
    user_id UUID PRIMARY KEY REFERENCES users(id),
    sms_enabled BOOLEAN DEFAULT true,
    phone_number TEXT,
    rate_limit_seconds INTEGER DEFAULT 60,
    quiet_hours_start TIME,
    quiet_hours_end TIME,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Enable RLS
ALTER TABLE notification_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_preferences ENABLE ROW LEVEL SECURITY;

-- 3. Create policies
DROP POLICY IF EXISTS "Users can view own notification log" ON notification_log;
CREATE POLICY "Users can view own notification log" ON notification_log
    FOR SELECT USING (true);

DROP POLICY IF EXISTS "Service can insert notifications" ON notification_log;
CREATE POLICY "Service can insert notifications" ON notification_log
    FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "Users can manage own preferences" ON notification_preferences;
CREATE POLICY "Users can manage own preferences" ON notification_preferences
    FOR ALL USING (true);

-- 4. Rate limiting function
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

-- 5. Create ginzatron user if not exists, then set up Noah's preferences
DO $$
DECLARE
    noah_id UUID;
BEGIN
    -- First ensure ginzatron user exists
    INSERT INTO users (id, github_handle, display_name, created_at, updated_at)
    VALUES (gen_random_uuid(), 'ginzatron', 'Noah', NOW(), NOW())
    ON CONFLICT (github_handle) DO NOTHING;

    -- Get Noah's user ID
    SELECT id INTO noah_id FROM users WHERE github_handle = 'ginzatron';

    -- Set up notification preferences
    IF noah_id IS NOT NULL THEN
        INSERT INTO notification_preferences (user_id, phone_number, sms_enabled, rate_limit_seconds)
        VALUES (noah_id, '+14125123593', true, 60)
        ON CONFLICT (user_id) DO UPDATE SET
            phone_number = '+14125123593',
            sms_enabled = true,
            rate_limit_seconds = 60;
        RAISE NOTICE 'Noah notification preferences set! Phone: +14125123593';
    ELSE
        RAISE NOTICE 'Could not find ginzatron user';
    END IF;
END $$;

-- 6. Verify setup
SELECT
    u.github_handle,
    u.display_name,
    np.phone_number,
    np.sms_enabled,
    np.rate_limit_seconds
FROM users u
LEFT JOIN notification_preferences np ON u.id = np.user_id
WHERE u.github_handle = 'ginzatron';
