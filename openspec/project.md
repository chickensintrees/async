# Async Project Conventions

## Project Name
Async - AI-Mediated Asynchronous Messaging

## Overview
A messaging platform where an AI agent intermediates between two parties, enhancing communication through summarization, tone adjustment, and intelligent queuing.

## Technology Stack
- **Client**: SwiftUI for native macOS
- **Backend**: Supabase (Postgres + Edge Functions)
- **AI**: Claude API for message processing
- **SMS**: Twilio for text message integration
- **Coordination**: GitHub + Protocol Thunderdome

## File Locations
- Specs: `openspec/specs/`
- Change proposals: `openspec/changes/`
- SwiftUI app: `app/`
- Dashboard: `dashboard/`
- Backend: `backend/`
  - Database schema: `backend/database/schema.sql`
  - Migrations: `backend/database/migrations/`
  - Edge Functions: `backend/supabase/functions/`
- Scripts: `scripts/`

## Naming Conventions
- Swift files: PascalCase (e.g., `MessageView.swift`)
- Spec domains: lowercase (e.g., `messaging/`, `ai-agent/`)
- Config files: kebab-case (e.g., `app-config.json`)
- Database migrations: `NNN_description.sql` (e.g., `001_sms_support.sql`)

## Design Principles
1. **Async-first** - Not real-time chat; embrace delays as a feature
2. **AI adds value** - Not just message passing; summarize, adjust, prioritize
3. **Privacy by design** - Sensitive content requires trust architecture
4. **Native feel** - SwiftUI for polished macOS experience
5. **Spec-driven** - Define behavior before implementing
6. **Documentation is truth** - All docs must reflect reality; update on every change
