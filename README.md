# Async

**AI-Mediated Asynchronous Messaging** — Built by humans and AI, for humans and AI.

## The Meta

This project is deliberately recursive: we're building an AI-mediated communication platform **using** AI-mediated communication. Bill (chickensintrees) and Noah (ginzatron) collaborate through Claude Code instances that:

- Share context via this repo's `CLAUDE.md`
- Coordinate file edits via `scripts/agent-lock.sh`
- Communicate through SMS with STEF (an AI participant)
- Run "Protocol Thunderdome" for AI-powered scrum standups

We're dogfooding the concept before it's even built. If two developers can collaborate effectively with AI mediation, the same patterns should work for any communication context.

## Concept

Traditional messaging is synchronous — you send, they reply, repeat. Async reimagines this with an AI agent that:

| Mode | How It Works | Use Case |
|------|--------------|----------|
| **Anonymous** | AI rewrites messages; recipient never sees original | Therapy, heated negotiations |
| **Assisted** | Everyone sees everything; AI summarizes and suggests | Dev collaboration, meetings |
| **Direct** | No AI involvement | Casual chat, private matters |

The AI adds value by:
- **Summarizing** long messages into digestible points
- **Adjusting tone** when emotions run high
- **Extracting action items** from conversations
- **Queuing intelligently** based on urgency
- **Responding on behalf** when appropriate (with approval)

## Current State

### App (SwiftUI Native macOS)

```
┌─────────────────────────────────────────────────────────────┐
│  [User Menu]                                      Async     │
├──────────┬──────────────────────────────────────────────────┤
│ Sidebar  │  Detail View                                     │
│          │                                                  │
│ Messages │  ┌─────────────┬────────────────────────────┐   │
│ Contacts │  │ Conv List   │  Conversation Detail       │   │
│ Dashboard│  │             │                            │   │
│ Backlog  │  │ • Chat 1    │  [Message bubbles]         │   │
│ Admin    │  │ • Chat 2    │  [AI mediation controls]   │   │
│          │  │ • Chat 3    │  [Compose area]            │   │
│          │  └─────────────┴────────────────────────────┘   │
└──────────┴──────────────────────────────────────────────────┘
```

**Tabs:**
- **Messages** — Conversations list + detail view with AI mediation
- **Contacts** — User directory with relationship management
- **Dashboard** — GitHub activity feed, leaderboard, AI trash talk
- **Backlog** — GitHub issues as kanban-style task board
- **Admin** — Connection management, system configuration

**Features:**
- **Image Attachments** — Click 📎 to attach images, preview before send, displayed inline in messages
- **AI Agent Chat** — Talk directly with STEF; agents respond to every message in 1:1 chats
- **Cross-Conversation Memory** — Agents remember facts from previous conversations
- **Real-time UI** — Optimistic updates, auto-scroll, responsive input

### Backend (Supabase)

Live database with:
- `users` — GitHub-linked profiles (human or agent type)
- `conversations` — Threads with mode and kind
- `conversation_participants` — Who's in each conversation (with per-user state)
- `messages` — Raw content + AI-processed versions + image attachments
- `message_reads` — Read receipts
- `agent_context` — Historical context for AI mediation

**Storage:** Supabase Storage bucket `message-attachments` for image uploads with RLS policies.

## Conversation Model

Based on research into Slack, iMessage, and Matrix patterns, Async uses a **room-first model** with **canonical 1:1 reuse**:

### Design Principles

| Pattern | Implementation | Rationale |
|---------|---------------|-----------|
| **Room-first** | Every DM, group, channel is a `conversation` | Clean edges, one mode per thread |
| **Canonical 1:1** | Same participants → same thread by default | "Message STEF" always lands in same place |
| **Explicit new thread** | User must opt-in to create duplicate | Prevents "where did we talk?" confusion |
| **Per-user state** | Mute, archive, read cursor per participant | Your inbox, your rules |

### Conversation Kinds

| Kind | Description | Mode Picker? |
|------|-------------|--------------|
| `direct_1to1` with human | 1:1 with another person | Yes |
| `direct_1to1` with agent | 1:1 with AI (STEF) | No (inherently assisted) |
| `direct_group` | Group with any participants | Yes |
| `channel` | Future: public/private channels | TBD |
| `system` | System notifications | No |

### Canonical Key

For 1:1 conversations, a canonical key ensures reuse:
```
dm:{minUserId}:{maxUserId}:{mode}
```

This prevents duplicate DMs and matches user expectation that "Message Noah" always goes to the same place.

### AI Agent Conversations

When chatting directly with an AI agent (like STEF), the communication mode picker is hidden because:
- Mode is for **human-to-human mediation**
- An agent conversation is inherently "assisted"
- The AI responds to every message (not just when @mentioned)

### SMS Integration (Twilio)

Text-based group chat where STEF participates as an AI member. Messages flow:
```
SMS → Twilio → Edge Function → Supabase → Claude API → Response → SMS
```

## Tech Stack

| Layer | Technology |
|-------|------------|
| Client | SwiftUI (macOS native) |
| Backend | Supabase (Postgres + Edge Functions) |
| AI | Claude API (Anthropic) |
| SMS | Twilio |
| Dev Tools | Claude Code, Protocol Thunderdome |

## Repository Structure

```
async/
├── README.md              # You are here
├── CLAUDE.md              # AI agent instructions (read this if you're Claude)
├── app/                   # SwiftUI application
│   ├── Package.swift
│   ├── Sources/Async/
│   │   ├── Models/        # AppState, data models, MessageAttachment
│   │   ├── Views/         # SwiftUI views
│   │   └── Services/      # ImageService, MediatorService, Gamification
│   └── scripts/
│       └── install.sh     # Build & install to /Applications
├── backend/
│   ├── database/
│   │   ├── schema.sql     # Core database schema
│   │   └── migrations/    # Database migrations
│   └── supabase/
│       └── functions/     # Edge Functions (webhooks)
├── scripts/
│   ├── thunderdome.sh     # AI scrum master
│   ├── agent-lock.sh      # Multi-agent file coordination
│   └── sms-context.sh     # Query SMS conversation history
├── openspec/              # Spec-driven development
│   ├── specs/             # Current specifications
│   └── changes/           # Proposed changes
└── .claude/               # Claude Code project config
    └── settings.json      # Enabled plugins, permissions
```

## Development

### Prerequisites

- macOS 14+ (Sonoma)
- Xcode 15+ or Swift toolchain
- Claude Code CLI (for AI-assisted development)
- Supabase account (for backend)

### Quick Start

```bash
# Clone and enter
git clone https://github.com/chickensintrees/async.git
cd async

# Build and install the app
./app/scripts/install.sh
open /Applications/Async.app

# Check project status (Thunderdome)
./scripts/thunderdome.sh
```

### For Claude Code Users

**Required plugins:**
```bash
# SwiftUI/iOS development (131 skills)
claude plugin marketplace add CharlesWiltgen/Axiom
claude plugin install axiom
```

**Read `CLAUDE.md`** for:
- Multi-agent coordination protocol
- File locking system
- Debrief procedures
- Code review workflow

### Multi-Agent Development

Multiple Claude Code instances can work simultaneously using `scripts/agent-lock.sh`:

```bash
# Check who's working on what
./scripts/agent-lock.sh status

# Claim a file before editing
./scripts/agent-lock.sh acquire app/Sources/Async/Views/MainView.swift "refactoring"

# Release when done
./scripts/agent-lock.sh release app/Sources/Async/Views/MainView.swift
```

### Testing

```bash
cd app && swift test
```

112 tests covering models, services, image handling, and view logic.

### Gamification

Commits are scored:
| Action | Points |
|--------|--------|
| Commit with tests | +50 |
| Small commit (<50 lines) | +10 |
| PR merged | +100 |
| Breaking CI | -100 |
| Untested code dump (>300 lines) | -75 |

Titles range from "Keyboard Polisher" (0-99) to "Code Demigod" (15000+).

## Contributing

1. Read `CLAUDE.md` and `openspec/AGENTS.md`
2. Check existing issues and specs
3. Create a feature branch
4. Write tests (untested code = negative points)
5. Submit PR for AI-managed review

## Contributors

- **chickensintrees** (Bill) — Human + STEF (Claude Code)
- **ginzatron** (Noah) — Human + Claude Code

---

*Built with Claude Code. Reviewed by Claude Code. Deployed by humans (for now).*
