# Async Database

## Current Provider: Supabase

**Project**: `ujokdwgpwruyiuioseir`
**Dashboard**: https://supabase.com/dashboard/project/ujokdwgpwruyiuioseir

We're using Supabase (Postgres) but the schema is designed to be portable.

## Dashboard

Supabase Studio provides a built-in UI dashboard:
- **Table Editor**: View/edit data in a spreadsheet-like interface
- **SQL Editor**: Run raw queries
- **Auth**: Manage users
- **Realtime**: Monitor subscriptions
- **Logs**: See what's happening

## Schema

See `schema.sql` for the full schema. Key tables:

| Table | Purpose |
|-------|---------|
| `users` | User profiles (GitHub handle, phone number) |
| `conversations` | Chat threads with mode (anonymous/assisted/direct) |
| `conversation_participants` | Who's in each conversation |
| `messages` | Messages with raw + processed content, source tracking |
| `message_reads` | Read receipts |
| `agent_context` | Historical context for AI mediation |

## Migrations

Migrations live in `migrations/` and should be run in order:

| Migration | Purpose |
|-----------|---------|
| `001_sms_support.sql` | Phone numbers, STEF user, SMS conversation |

To run a migration: Paste contents into Supabase SQL Editor and execute.

## Special Records

| Type | ID | Purpose |
|------|-----|---------|
| STEF User | `00000000-0000-0000-0000-000000000001` | AI agent participant |
| SMS Conversation | `00000000-0000-0000-0000-000000000002` | Bill + Noah + STEF group chat |

## Setup

1. Create a Supabase project at https://supabase.com
2. Go to SQL Editor
3. Paste and run `schema.sql`
4. Run all migrations in `migrations/` folder
5. Enable Realtime for `messages` table (Database → Replication)
6. Copy your project URL and keys to `.env.local`

## Environment Variables

Create `backend/.env.local` (gitignored):

```bash
SUPABASE_URL=https://ujokdwgpwruyiuioseir.supabase.co
SUPABASE_ANON_KEY=eyJ...
SUPABASE_SERVICE_KEY=eyJ...  # Keep secret!
ANTHROPIC_API_KEY=sk-ant-...
TWILIO_ACCOUNT_SID=AC...
TWILIO_AUTH_TOKEN=...
TWILIO_PHONE_NUMBER=+1...
```

## Switching Providers

The schema is standard Postgres. To switch:

1. **To raw Postgres**: Run schema.sql, remove Supabase-specific RLS policies
2. **To SQLite**: Convert types (UUID → TEXT, TIMESTAMPTZ → TEXT), remove RLS
3. **To Firebase**: Would need full rewrite (document DB vs relational)

## Row Level Security (RLS)

Supabase uses RLS for access control. Current policies:
- Users can read all user profiles
- Users can only update their own profile
- Users can only see conversations they're in
- Users can only see/send messages in their conversations
- Service role (Edge Functions) can read/write all tables
