# Async

An asynchronous messaging application with an AI agent intermediary.

## Concept

Traditional messaging is synchronous - you send, they reply, you reply. Async reimagines this with an AI agent in the middle that:

- **Summarizes** long messages into digestible points
- **Adjusts tone** when emotions run high
- **Extracts action items** from conversations
- **Queues intelligently** based on urgency and context
- **Responds on behalf** when appropriate (with approval)

## Use Cases

- **Customer ↔ Company**: AI handles routine inquiries, escalates intelligently
- **Student ↔ Teacher**: AI helps students articulate questions, batches responses for teachers
- **Individual ↔ Therapist**: AI checks in between sessions, flags urgent concerns
- **Developer ↔ Developer**: AI mediates collaboration (we dogfood this!)

## Tech Stack

- **Client**: SwiftUI (native macOS)
- **Backend**: Supabase (Postgres + Edge Functions)
- **AI**: Claude API
- **SMS Integration**: Twilio (for SMS group chat with AI)

## Current Features

- **Database**: Live on Supabase with users, conversations, messages, read receipts
- **Dashboard**: SwiftUI app for monitoring repo activity with gamification
- **SMS Group Chat**: Text-based communication with STEF (AI) as a participant
- **Protocol Thunderdome**: AI scrum master for project coordination

## Repository Structure

```
async/
├── CLAUDE.md              # AI agent instructions
├── README.md              # You are here
├── openspec/              # Spec-driven development
│   ├── specs/             # Current specifications
│   └── changes/           # Proposed changes
├── dashboard/             # GitHub monitoring app (SwiftUI)
├── scripts/               # Utility scripts (thunderdome, sms-context)
├── backend/
│   ├── database/          # Schema and migrations
│   └── supabase/          # Edge Functions (webhooks)
└── app/                   # Main application (future)
```

## Development

This project uses spec-driven development. See `openspec/` for specifications.

### For Claude Code Users

Read `CLAUDE.md` for project-specific instructions. Both contributors work with Claude Code instances that coordinate via GitHub.

### Quick Start

```bash
# Run the dashboard
cd dashboard && ./scripts/start-dashboard.sh

# Check project status
./scripts/thunderdome.sh

# Query SMS conversation history (for Claude Code sync)
./scripts/sms-context.sh
```

## Contributors

- chickensintrees (Bill)
- ginzatron (Noah)
