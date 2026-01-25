# Async Database

## Current Provider: Supabase

We're using Supabase (Postgres) but the schema is designed to be portable.

## Dashboard

Supabase Studio provides a built-in UI dashboard:
- **Table Editor**: View/edit data in a spreadsheet-like interface
- **SQL Editor**: Run raw queries
- **Auth**: Manage users
- **Realtime**: Monitor subscriptions
- **Logs**: See what's happening

Access at: https://supabase.com/dashboard/project/YOUR_PROJECT_REF

## Schema

See `schema.sql` for the full schema. Key tables:

| Table | Purpose |
|-------|---------|
| `users` | User profiles (linked to GitHub) |
| `conversations` | Chat threads with mode (anonymous/assisted/direct) |
| `conversation_participants` | Who's in each conversation |
| `messages` | The actual messages with raw + processed content |
| `message_reads` | Read receipts |

## Setup

1. Create a Supabase project at https://supabase.com
2. Go to SQL Editor
3. Paste and run `schema.sql`
4. Enable Realtime for `messages` table (Database → Replication)
5. Copy your project URL and keys to `.env.local`

## Environment Variables

Create `backend/.env.local` (gitignored):

```
SUPABASE_URL=https://xxxxx.supabase.co
SUPABASE_ANON_KEY=eyJ...
SUPABASE_SERVICE_KEY=eyJ...  # Keep secret!
```

## Switching Providers

The schema is standard Postgres. To switch:

1. **To raw Postgres**: Run schema.sql, remove Supabase-specific RLS policies
2. **To SQLite**: Convert types (UUID → TEXT, TIMESTAMPTZ → TEXT), remove RLS
3. **To Firebase**: Would need full rewrite (document DB vs relational)

The abstraction layer in `database.swift` (future) will hide provider details from the app.

## Row Level Security (RLS)

Supabase uses RLS for access control. Current policies:
- Users can read all user profiles
- Users can only update their own profile
- Users can only see conversations they're in
- Users can only see/send messages in their conversations
