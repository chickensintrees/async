# Async Agent Instructions

> **Configuration-as-code for AI agents** - Based on [GitHub Agent HQ patterns](https://www.digitalapplied.com/blog/github-agent-hq-multi-agent-platform)

## Agent Configuration

### Supported Agents
| Agent ID | Owner | Primary Role |
|----------|-------|--------------|
| `bill-main` | chickensintrees | Primary development |
| `bill-secondary` | chickensintrees | Parallel tasks |
| `noah-main` | ginzatron | Primary development |
| `noah-secondary` | ginzatron | Parallel tasks |

### Agent Capabilities
All agents can:
- Read/write code in `app/`, `backend/`, `scripts/`
- Run tests and builds
- Commit and push to `main` (with coordination)
- Create and merge PRs
- Query shared context via SMS/Supabase

## Core Workflow

### Before ANY Code Change
```bash
# 1. Sync with remote
git fetch && git status

# 2. Check for active agents
./scripts/agent-lock.sh status

# 3. Acquire locks for files you'll edit
./scripts/agent-lock.sh acquire <file> "description"

# 4. Pull latest
git pull --rebase origin main
```

### Spec-Driven Development
1. **Read CLAUDE.md first** - Understand project context and rules
2. **Check specs** - Read relevant spec in `openspec/specs/`
3. **Propose changes** - Create `openspec/changes/[name]/proposal.md` before coding
4. **Implement to spec** - Satisfy all SHALL/MUST requirements
5. **Update docs** - README, CLAUDE.md, and any affected documentation

### Adding a Feature
1. Create `openspec/changes/[feature-name]/proposal.md`
2. Define requirements with scenarios
3. Get user approval
4. Implement to spec
5. Archive to `openspec/specs/`
6. Update README, CLAUDE.md, and affected docs

### Fixing a Bug
1. Check if spec covers the behavior
2. If spec is wrong → create change proposal
3. If implementation is wrong → fix to match spec

## Multi-Agent Coordination

### The Golden Rules
1. **Lock before edit** - Always acquire lock on files you'll modify
2. **Pull before push** - Always `git pull --rebase` before pushing
3. **Never force push main** - Rewriting shared history breaks everything
4. **Communicate intent** - Use SMS/@stef for urgent coordination

### Conflict Resolution Matrix

| Situation | Action |
|-----------|--------|
| Lock held by active agent | Wait or coordinate via SMS |
| Lock is stale (>10 min) | Run `./scripts/agent-lock.sh cleanup`, then acquire |
| Git merge conflict | STOP, assess ownership, resolve by category |
| Both agents want same file | First lock wins; escalate to user if critical |
| Agent pushed broken code | Revert with `git revert HEAD`, notify user |

### Resolution by File Type
| File Type | Strategy |
|-----------|----------|
| Swift code | Keep newer logic; merge if complementary |
| Config/JSON | Merge manually; keep all valid entries |
| Documentation | Keep more complete; merge additions |
| Generated files | Regenerate from source |

### Session Handoff
**Outgoing agent:**
1. Commit with `"WIP: <description> [handoff to <agent>]"`
2. Push to origin
3. Release all locks
4. Document state in session log

**Incoming agent:**
1. `git pull --rebase origin main`
2. Check locks and recent commits
3. Acquire locks for continuation work

## Key Protocols

### Protocol Thunderdome
AI scrum master routine. Trigger: "thunderdome" or "run scrum"
- Fetches GitHub state (commits, PRs, issues)
- Calculates gamification scores
- Reports blockers and action items
- Checks documentation staleness

### Debrief Protocol
End-of-session routine. Trigger: "debrief" or "end session"
1. Run tests (MANDATORY - all must pass)
2. Commit and push all changes
3. Review and update documentation
4. Run Thunderdome for final status
5. Create session log

## Current Domains
| Domain | Path | Description |
|--------|------|-------------|
| messaging | `app/Sources/Async/` | Core message flow (SwiftUI) |
| ai-agent | Claude API | AI intermediary behavior |
| client | `app/` | SwiftUI macOS application |
| backend | `backend/` | Supabase Edge Functions, database |
| sms | `backend/supabase/functions/sms-webhook/` | Twilio SMS + STEF |

## Shared Context

### SMS Conversation (Supabase)
Both Claude Code instances sync via shared SMS history:
```bash
./scripts/sms-context.sh       # Last 50 messages
./scripts/sms-context.sh 100   # Last 100 messages
```

### When to Use SMS for Coordination
- Urgent: "I'm about to refactor Models, heads up"
- Blocked: "Need you to release lock on MainView"
- Handoff: "Pushed WIP for Kanban, picking up tomorrow"
- Question: "Should we use NavigationStack or NavigationSplitView?"

## Emergency Procedures

### Agent Crashed Mid-Edit
1. Other agent runs: `./scripts/agent-lock.sh cleanup`
2. Check `git status` for uncommitted changes
3. Either commit the WIP or stash: `git stash`
4. Continue work normally

### Broken Code Pushed to Main
```bash
# Quick revert (last commit)
git revert HEAD --no-edit && git push

# Multiple bad commits
git log --oneline -10  # Find last good commit
git revert <bad>..<HEAD> --no-edit && git push
```

### Complete Repository Reset (NUCLEAR - user approval required)
```bash
git fetch origin
git reset --hard origin/main
# WARNING: Loses all local changes
```
