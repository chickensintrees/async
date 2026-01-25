# Async - AI-Mediated Messaging

## Project Overview
An asynchronous messaging application where an AI agent acts as an intermediary between parties:
- Customers ↔ Companies
- Students ↔ Teachers
- Individuals ↔ Therapists

The AI doesn't just pass messages through - it adds value by summarizing, adjusting tone, extracting action items, and potentially responding on behalf of parties when appropriate.

## Technology Stack
- **Client**: SwiftUI (native macOS app)
- **Backend**: TBD (likely Swift + Claude API, or Python/FastAPI)
- **AI**: Claude API for message processing

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
- Use GitHub Issues for tracking work
- PRs require review before merge

## Design Principles
1. **AI as intermediary, not replacement** - The AI enhances communication, doesn't replace human connection
2. **Async-first** - Not trying to be real-time chat; embrace the asynchronous nature
3. **Privacy-conscious** - Messages contain sensitive content; design for trust
4. **Native experience** - SwiftUI for polished macOS feel

## Key Questions to Resolve
- [ ] Does the AI have autonomy to respond, or always queues for human approval?
- [ ] Same app for both parties, or different experiences?
- [ ] Local-first (messages stored on device) or cloud-synced?
- [ ] What's the authentication/identity model?
