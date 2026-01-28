-- Trigger function to auto-update conversation.last_message_at when messages are inserted
CREATE OR REPLACE FUNCTION update_conversation_last_message_at()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE conversations 
    SET last_message_at = NEW.created_at
    WHERE id = NEW.conversation_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger on messages table
DROP TRIGGER IF EXISTS trigger_update_last_message_at ON messages;
CREATE TRIGGER trigger_update_last_message_at
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION update_conversation_last_message_at();
