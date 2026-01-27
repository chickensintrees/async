# SMS Webhook - STEF Group Chat

Supabase Edge Function that enables SMS group chat between Bill, Noah, and STEF.

## How It Works

```
┌─────────────┐     ┌─────────────┐
│ Bill's SMS  │     │ Noah's SMS  │
└──────┬──────┘     └──────┬──────┘
       │                   │
       ▼                   ▼
┌─────────────────────────────────┐
│     Twilio Phone Number         │
└──────────────┬──────────────────┘
               │
               ▼
┌─────────────────────────────────┐
│  This Edge Function (webhook)  │
│  - Stores message in Supabase   │
│  - Checks for @STEF mention     │
│  - Calls Claude API if needed   │
│  - Sends response via Twilio    │
└─────────────────────────────────┘
```

## Setup

### 1. Run the Migration

In Supabase SQL Editor, run:
```sql
-- Contents of backend/database/migrations/001_sms_support.sql
```

### 2. Create Twilio Account

1. Sign up at https://www.twilio.com
2. Get a phone number (~$1/month)
3. Note your Account SID and Auth Token

### 3. Set Environment Variables

In Supabase Dashboard → Edge Functions → sms-webhook → Settings:

```
ANTHROPIC_API_KEY=sk-ant-...
TWILIO_ACCOUNT_SID=AC...
TWILIO_AUTH_TOKEN=...
TWILIO_PHONE_NUMBER=+1...
```

### 4. Deploy the Function

```bash
cd backend/supabase
supabase functions deploy sms-webhook
```

### 5. Configure Twilio Webhook

In Twilio Console → Phone Numbers → Your Number:
- Messaging → Webhook URL: `https://<project-ref>.supabase.co/functions/v1/sms-webhook`
- Method: POST

### 6. Register Phone Numbers

Add Bill and Noah's phone numbers to the users table:

```sql
UPDATE users SET phone_number = '+1XXXXXXXXXX' WHERE github_handle = 'chickensintrees';
UPDATE users SET phone_number = '+1XXXXXXXXXX' WHERE github_handle = 'ginzatron';
```

### 7. Add Users to SMS Conversation

```sql
INSERT INTO conversation_participants (conversation_id, user_id)
SELECT '00000000-0000-0000-0000-000000000002', id
FROM users WHERE github_handle IN ('chickensintrees', 'ginzatron');
```

## Usage

### Trigger STEF Response

Any of these patterns in a message will trigger STEF:
- `@stef`
- `stef` (as a word)
- `@claude`
- `hey stef`

### Query Conversation (for Claude Code sync)

Both Bill's and Noah's Claude Code can run:
```bash
./scripts/sms-context.sh
```

This fetches the shared conversation history from Supabase.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `SUPABASE_URL` | Auto-provided by Supabase |
| `SUPABASE_SERVICE_ROLE_KEY` | Auto-provided by Supabase |
| `ANTHROPIC_API_KEY` | Your Claude API key |
| `TWILIO_ACCOUNT_SID` | From Twilio Console |
| `TWILIO_AUTH_TOKEN` | From Twilio Console |
| `TWILIO_PHONE_NUMBER` | Your Twilio phone number |
