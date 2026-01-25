# Async - AI-Mediated Messaging

## Rules for Claude Code

### GitHub Sync Rule
**IMPORTANT**: Whenever design decisions, specs, or significant documentation changes are made locally, ALWAYS push them to GitHub so collaborators stay in sync. This includes:
- Updates to CLAUDE.md
- New or modified specs in openspec/
- Design documents
- Any architectural decisions

After making local changes, commit and push to origin/main (or create a PR for larger changes).

### Collaboration First
This is a collaborative project. Before building features:
1. Document the idea in openspec/changes/ or GitHub Issues
2. Get input from collaborators (ginzatron)
3. Reach consensus, then build

## Project Overview

An asynchronous messaging application where an AI agent acts as an intermediary between parties:
- Customers ↔ Companies
- Students ↔ Teachers
- Individuals ↔ Therapists
- **Developers ↔ Developers** (dogfooding - we use this to build this)

The AI doesn't just pass messages through - it adds value by summarizing, adjusting tone, extracting action items, and potentially responding on behalf of parties when appropriate.

## Dogfooding Strategy

Once MVP is working, Bill (chickensintrees) and ginzatron will use Async to coordinate development of Async itself. This gives us:
- Real usage data from day one
- Immediate feedback on friction points
- Proof of concept for other use cases

## Communication Modes

Three distinct modes for how the AI participates:

### 1. Anonymous (Agent-Mediated)
```
┌─────┐          ┌─────────┐          ┌─────┐
│  A  │ ──raw──▶ │  Agent  │ ──proc─▶ │  B  │
└─────┘          └─────────┘          └─────┘
```
B only sees the agent's processed version. Never sees A's raw words.
**Use case**: Therapy, customer support, heated negotiations

### 2. Assisted (Group with Agent)
```
┌─────┐     ┌─────────┐     ┌─────┐
│  A  │◀───▶│  Agent  │◀───▶│  B  │
└──┬──┘     └─────────┘     └──┬──┘
   └────────────────────────────┘
```
Everyone sees everything. Agent can summarize, suggest, translate.
**Use case**: Dev collaboration, meetings, complex projects

### 3. Direct (No Agent)
```
┌─────┐          ┌─────┐
│  A  │◀────────▶│  B  │
└─────┘          └─────┘
```
Just humans. Agent excluded entirely.
**Use case**: Casual chat, private matters

## Data Model (Draft)

```
Conversation
├── id
├── mode: anonymous | assisted | direct
├── participants: [user_ids]
├── created_at

Message
├── id
├── conversation_id
├── sender_id
├── content_raw          # What sender actually typed
├── content_processed    # What agent transformed it to (if applicable)
├── visible_to: [user_ids]  # Who can see raw vs processed
├── timestamp

User
├── id
├── github_handle
├── display_name
```

## Technology Stack

- **Client**: SwiftUI (native macOS app)
- **Backend**: Supabase (Postgres)
  - Project: `ujokdwgpwruyiuioseir`
  - Dashboard: https://supabase.com/dashboard/project/ujokdwgpwruyiuioseir
  - Credentials in `backend/.env.local` (gitignored)
- **AI**: Claude API for message processing

### Database Tables (Live)
- `users` - User profiles linked to GitHub
- `conversations` - Chat threads with mode (anonymous/assisted/direct)
- `conversation_participants` - Who's in each conversation
- `messages` - Raw content + AI-processed content
- `message_reads` - Read receipts
- `agent_context` - Historical context for AI mediation (session logs, decisions, background)

Schema: `backend/database/schema.sql`

## Repository Structure

```
async/
├── CLAUDE.md           # You are here - project instructions
├── README.md           # Public-facing documentation
├── openspec/           # Spec-driven development
│   ├── project.md      # Project conventions
│   ├── AGENTS.md       # Instructions for AI agents
│   ├── specs/          # Current specifications
│   └── changes/        # Proposed changes
├── app/                # SwiftUI application (future)
└── backend/            # Backend service (future)
```

## Development Workflow

### Spec-Driven Development
1. **Check specs first** - Before implementing, read relevant specs in `openspec/specs/`
2. **Propose changes** - Create a change folder in `openspec/changes/` before coding
3. **Implement to spec** - Follow all SHALL/MUST requirements
4. **Update specs** - Archive completed changes to specs/

### Collaboration
- Bill (chickensintrees) and ginzatron are collaborating on this project
- Use GitHub Issues for discussion and tracking
- PRs require review before merge
- Major decisions documented in openspec/

## Design Principles

1. **AI as intermediary, not replacement** - The AI enhances communication, doesn't replace human connection
2. **Async-first** - Not trying to be real-time chat; embrace the asynchronous nature
3. **Privacy-conscious** - Messages contain sensitive content; design for trust
4. **Native experience** - SwiftUI for polished macOS feel
5. **Dogfood early** - Use the tool to build the tool

## Open Questions

- [x] Database choice - **Supabase (Postgres)** ✓
- [ ] Does the AI have autonomy to respond, or always queues for human approval?
- [ ] Same app for both parties, or different UX per role?
- [ ] What's the authentication/identity model?
- [ ] First feature to build: message input + AI processing, or two-user sync?
