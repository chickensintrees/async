# Async Project Conventions

## Project Name
Async - AI-Mediated Asynchronous Messaging

## Overview
A messaging platform where an AI agent intermediates between two parties, enhancing communication through summarization, tone adjustment, and intelligent queuing.

## Technology Stack
- SwiftUI for native macOS client
- Claude API for AI processing
- Backend TBD (Swift or Python)

## File Locations
- Specs: `openspec/specs/`
- Change proposals: `openspec/changes/`
- SwiftUI app: `app/`
- Backend: `backend/`

## Naming Conventions
- Swift files: PascalCase (e.g., `MessageView.swift`)
- Spec domains: lowercase (e.g., `messaging/`, `ai-agent/`)
- Config files: kebab-case (e.g., `app-config.json`)

## Design Principles
1. **Async-first** - Not real-time chat; embrace delays as a feature
2. **AI adds value** - Not just message passing; summarize, adjust, prioritize
3. **Privacy by design** - Sensitive content requires trust architecture
4. **Native feel** - SwiftUI for polished macOS experience
5. **Spec-driven** - Define behavior before implementing
