# Async Agent Instructions

## For Claude Code

When working on Async:

1. **Read CLAUDE.md first** - Understand the project context
2. **Check specs before implementing** - Read relevant spec in `openspec/specs/`
3. **Propose changes properly** - Create a change folder in `openspec/changes/` with proposal.md before coding
4. **Follow the spec** - Implementation must satisfy all SHALL/MUST requirements
5. **Update specs after** - When implementation is complete, archive changes to specs/

## Spec-Driven Workflow

### Adding a Feature
1. Create `openspec/changes/[feature-name]/proposal.md`
2. Define requirements with scenarios
3. Get user approval
4. Implement to spec
5. Archive to `openspec/specs/`

### Fixing a Bug
1. Check if spec covers the behavior
2. If spec is wrong, create a change proposal
3. If implementation is wrong, fix to match spec

## Collaboration Notes
- This is a collaborative project between Bill and ginzatron
- Coordinate via GitHub Issues and PRs
- Major architectural decisions should be discussed before implementing
- Both collaborators may be working with their own Claude Code instances

## Current Domains (to be defined)
- `messaging/` - Core message flow and storage
- `ai-agent/` - AI intermediary behavior
- `client/` - SwiftUI application
- `backend/` - API and persistence
