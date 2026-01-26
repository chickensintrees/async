-- Add phone number directly to users table
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone_number TEXT;

-- Update Noah's phone number
UPDATE users SET phone_number = '+14125123593' WHERE github_handle = 'ginzatron';

-- Verify
SELECT github_handle, display_name, phone_number FROM users;
