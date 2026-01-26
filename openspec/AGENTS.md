# Async Agent Instructions

## For Claude Code

When working on Async:

1. **Read CLAUDE.md first** - Understand the project context
2. **Check specs before implementing** - Read relevant spec in `openspec/specs/`
3. **Propose changes properly** - Create a change folder in `openspec/changes/` with proposal.md before coding
4. **Follow the spec** - Implementation must satisfy all SHALL/MUST requirements
5. **Update specs after** - When implementation is complete, archive changes to specs/
6. **Update ALL documentation** - Any change that affects behavior must update relevant docs

## Spec-Driven Workflow

### Adding a Feature
1. Create `openspec/changes/[feature-name]/proposal.md`
2. Define requirements with scenarios
3. Get user approval
4. Implement to spec
5. Archive to `openspec/specs/`
6. **Update README, CLAUDE.md, and any affected docs**

### Fixing a Bug
1. Check if spec covers the behavior
2. If spec is wrong, create a change proposal
3. If implementation is wrong, fix to match spec

## Collaboration Notes
- This is a collaborative project between chickensintrees (Bill) and ginzatron (Noah)
- Coordinate via GitHub Issues and PRs
- Major architectural decisions should be discussed before implementing
- Both collaborators work with their own Claude Code instances
- **Claude Code instances share context via Supabase** (SMS conversation history)

## Key Protocols

### Protocol Thunderdome
AI scrum master routine. Triggered by "thunderdome" or "run scrum":
- Checks repo status (commits, PRs, issues)
- Calculates gamification scores
- Reports blockers and action items

### Debrief Protocol
End-of-session routine. Triggered by "debrief":
- Commits and pushes all changes
- Reviews and updates documentation
- Runs Thunderdome for final status
- Creates session log

## Current Domains
- `messaging/` - Core message flow and storage (Supabase)
- `ai-agent/` - AI intermediary behavior (Claude API)
- `client/` - SwiftUI application
- `backend/` - Supabase Edge Functions, database
- `sms/` - Twilio SMS integration with STEF

## Shared Context

Both Claude Code instances can sync via:
```bash
./scripts/sms-context.sh    # Query SMS conversation history
```

This ensures both Bill's and Noah's Claude Code have the same understanding of ongoing discussions.
