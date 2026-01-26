-- Enable the pg_net extension for HTTP calls
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- Create a function that calls the edge function
CREATE OR REPLACE FUNCTION notify_new_message_webhook()
RETURNS TRIGGER AS $$
BEGIN
    -- Only notify for human messages (not AI)
    IF NEW.is_from_agent = false THEN
        PERFORM net.http_post(
            url := 'https://ujokdwgpwruyiuioseir.supabase.co/functions/v1/notify-sms',
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVqb2tkd2dwd3J1eWl1aW9zZWlyIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2OTM3MzQyNCwiZXhwIjoyMDg0OTQ5NDI0fQ.cgViglDmJ1OjR3wLi28iqcEPaBHD0H4jnXG182jebhY'
            ),
            body := jsonb_build_object(
                'type', 'INSERT',
                'table', 'messages',
                'record', jsonb_build_object(
                    'id', NEW.id,
                    'conversation_id', NEW.conversation_id,
                    'sender_id', NEW.sender_id,
                    'content_raw', NEW.content_raw,
                    'created_at', NEW.created_at
                )
            )
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
    EXECUTE FUNCTION notify_new_message_webhook();
