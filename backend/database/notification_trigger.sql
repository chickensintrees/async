-- Database trigger to call SMS notification function
-- Run this in Supabase SQL Editor AFTER deploying the edge function

-- Create the webhook trigger function
CREATE OR REPLACE FUNCTION notify_new_message()
RETURNS TRIGGER AS $$
DECLARE
    webhook_url TEXT;
BEGIN
    -- The edge function URL (set this after deploying)
    webhook_url := current_setting('app.notify_sms_url', true);

    -- Only notify on new messages (not AI processing updates)
    IF webhook_url IS NOT NULL AND NEW.is_from_agent = false THEN
        PERFORM net.http_post(
            url := webhook_url,
            headers := '{"Content-Type": "application/json"}'::jsonb,
            body := json_build_object(
                'type', 'INSERT',
                'table', 'messages',
                'record', json_build_object(
                    'id', NEW.id,
                    'conversation_id', NEW.conversation_id,
                    'sender_id', NEW.sender_id,
                    'content_raw', NEW.content_raw,
                    'created_at', NEW.created_at
                )
            )::text
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create the trigger
DROP TRIGGER IF EXISTS on_new_message_notify ON messages;
CREATE TRIGGER on_new_message_notify
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION notify_new_message();

-- Note: You'll need to enable the pg_net extension in Supabase Dashboard
-- Go to: Database > Extensions > Search "pg_net" > Enable
