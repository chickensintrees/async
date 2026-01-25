# Proposal: Initial Architecture

**Status**: Draft - Awaiting Collaborator Input
**Author**: Bill (chickensintrees)
**Date**: 2026-01-25

## Summary

Define the core architecture for Async before writing any code. This proposal outlines communication modes, data model, and technology choices for discussion.

## Context

Async is an AI-mediated messaging app. The core innovation is that an AI agent can sit between two parties, adding value through summarization, tone adjustment, and intelligent queuing.

We (Bill and ginzatron) will dogfood this tool to coordinate our own development work.

## Proposal

### Communication Modes

The app supports three modes:

#### 1. Anonymous (Agent-Mediated)
- Party A sends a message
- AI processes it (summarizes, adjusts tone, etc.)
- Party B only sees the processed version
- B never sees A's raw words
- **Use case**: Therapy, customer support, heated negotiations

#### 2. Assisted (Group with Agent)
- Both parties see all messages
- AI is a participant that can summarize, suggest, translate
- Like a group chat with a helpful bot
- **Use case**: Dev collaboration, meetings, complex projects

#### 3. Direct (No Agent)
- Just two humans, no AI
- Agent is excluded entirely
- **Use case**: Casual chat, private matters

### Data Model

```
Conversation
├── id: UUID
├── mode: anonymous | assisted | direct
├── participants: [user_ids]
├── created_at: timestamp

Message
├── id: UUID
├── conversation_id: UUID
├── sender_id: UUID
├── content_raw: string         # Original message
├── content_processed: string?  # AI-transformed (if applicable)
├── visible_to: [user_ids]      # Who sees raw vs processed
├── timestamp: timestamp

User
├── id: UUID
├── github_handle: string
├── display_name: string
```

### Technology Options

#### Client
- **SwiftUI** (native macOS) - agreed

#### Backend/Database

| Option | Pros | Cons |
|--------|------|------|
| SQLite (local) | Simple, no server | Sync between users is hard |
| GitHub files | Already have access | Clunky, merge conflicts |
| Supabase | Real backend, real-time, free tier | External dependency |
| Firebase | Real-time sync, mature | Google dependency |
| CloudKit | Apple-native | Apple-only, complex |

**Recommendation**: Start with Supabase. Real backend, real-time subscriptions, generous free tier, easy auth.

#### AI
- **Claude API** - agreed

### MVP Candidates

Two options for first feature:

**Option A: Message Input + AI Processing**
- Build compose UI
- Send to Claude API
- Display processed output
- Proves: AI transformation is useful
- Can test solo

**Option B: Two-User Sync**
- Build send/receive between two users
- No AI yet
- Proves: We can sync messages
- Requires both users

**Recommendation**: Depends on what we want to validate first. AI value prop (A) or infrastructure (B)?

## Open Questions

1. Which database/backend should we use?
2. First feature: AI processing or user sync?
3. Should we start with just one communication mode (assisted) for simplicity?
4. Auth: GitHub OAuth? Apple Sign-In? Both?

## Next Steps

1. @ginzatron reviews and comments
2. Resolve open questions
3. Write spec for first feature
4. Build

---

**Please comment on GitHub Issue #2 with your thoughts.**
