# SMS Notifications Setup

Send text messages to users when they receive new messages in Async.

## Features
- SMS notifications via Twilio
- Rate limiting: 1 notification per minute max per user
- Quiet hours support (optional)
- Per-user preferences

## Setup Steps

### 1. Create Twilio Account

1. Go to https://www.twilio.com/try-twilio
2. Sign up for a free account
3. Get a phone number (free trial includes one)
4. Note your credentials:
   - Account SID (starts with AC...)
   - Auth Token
   - Phone Number (e.g., +1234567890)

### 2. Run Database Migration

In Supabase SQL Editor (https://supabase.com/dashboard/project/ujokdwgpwruyiuioseir/sql):

```sql
-- Run the contents of: backend/database/notifications.sql
```

### 3. Enable pg_net Extension

In Supabase Dashboard:
1. Go to Database > Extensions
2. Search for "pg_net"
3. Enable it

### 4. Deploy Edge Function

```bash
cd /Users/BillMoore/async/backend

# Install Supabase CLI if needed
brew install supabase/tap/supabase

# Login
supabase login

# Link to project
supabase link --project-ref ujokdwgpwruyiuioseir

# Set secrets
supabase secrets set TWILIO_ACCOUNT_SID=your_account_sid
supabase secrets set TWILIO_AUTH_TOKEN=your_auth_token
supabase secrets set TWILIO_PHONE_NUMBER=+1234567890

# Deploy function
supabase functions deploy notify-sms
```

### 5. Create Database Trigger

After deploying, get the function URL and run the trigger SQL:

```sql
-- Set the webhook URL (replace with your actual function URL)
ALTER DATABASE postgres SET app.notify_sms_url = 'https://ujokdwgpwruyiuioseir.supabase.co/functions/v1/notify-sms';

-- Then run: backend/database/notification_trigger.sql
```

## Configuration

### Noah's Settings (Pre-configured)
- Phone: +1 (412) 512-3593
- Rate limit: 60 seconds
- SMS enabled: true

### Add More Users

```sql
INSERT INTO notification_preferences (user_id, phone_number, sms_enabled, rate_limit_seconds)
SELECT id, '+1XXXXXXXXXX', true, 60
FROM users WHERE github_handle = 'username';
```

### Quiet Hours

```sql
UPDATE notification_preferences
SET quiet_hours_start = '22:00', quiet_hours_end = '08:00'
WHERE user_id = (SELECT id FROM users WHERE github_handle = 'ginzatron');
```

## Testing

Send a test message in the app, and Noah should receive an SMS within a few seconds (if not rate-limited).

## Costs

Twilio pricing (as of 2024):
- SMS to US numbers: ~$0.0079/message
- Free trial includes $15 credit
