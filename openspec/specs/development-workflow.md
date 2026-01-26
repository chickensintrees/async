# Development Workflow Spec

## Overview
Standard workflow for Bill and Noah to go from feature request to deployed, tested code.

## The Golden Rules

1. **Never end a session with uncommitted code** - If you wrote it, commit it
2. **Never commit directly to main without tests passing** - Use branches for big features
3. **Thunderdome is the source of truth** - Run it to know project status

## Workflow Steps

### 1. CAPTURE (Feature Request)
```
WHERE: GitHub Issues
WHO: Anyone
WHAT:
  - Create issue with clear title
  - Add labels: feature|bug|chore + priority:high|medium|low
  - Add to backlog (label: backlog)
```

### 2. PLAN (For non-trivial features)
```
WHERE: openspec/changes/YYYYMMDD-feature-name/
WHO: Implementer
WHAT:
  - spec.md with approach
  - Get thumbs up from other dev (comment on issue)
```

### 3. IMPLEMENT
```
WHERE: Feature branch (feature/short-name) OR main for small fixes
WHO: Implementer
WHAT:
  - Write code
  - Write tests (MUSThave for services, SHOULD have for views)
  - Test locally: swift build && swift test
```

### 4. COMMIT & PUSH
```
WHEN: End of every coding session, minimum
HOW:
  - git add -A
  - git commit -m "Clear message describing what changed"
  - git push origin <branch>
```

### 5. PR & REVIEW (For feature branches)
```
WHERE: GitHub PR
WHO: Other dev reviews
WHAT:
  - PR description with summary
  - Tests passing (CI will check)
  - Reviewer approves or requests changes
```

### 6. MERGE & DEPLOY
```
WHO: PR author after approval
HOW:
  - Squash merge to main
  - Delete feature branch
  - Build release: ./scripts/build-release.sh
  - Deploy: cp to /Applications/Async.app
```

## Quick Commits (Small Fixes)

For typos, small bug fixes, config changes:
```bash
# OK to commit directly to main
git add -A
git commit -m "Fix: description"
git push origin main
```

## Session Boundaries

### Starting a Session
```bash
cd ~/async
git pull origin main           # Get latest
./scripts/thunderdome.sh       # Check status
```

### Ending a Session
```bash
git status                     # What's uncommitted?
git add -A                     # Stage everything
git commit -m "Session: what I did"
git push origin main           # Push it
./scripts/thunderdome.sh       # Verify status
```

## Thunderdome Integration

Protocol Thunderdome now checks:
- [ ] Uncommitted local changes (WARN if any)
- [ ] Unpushed commits (WARN if any)
- [ ] Open PRs needing review
- [ ] CI status on main
- [ ] Test coverage trends

## File Ownership

```
Bill (chickensintrees):     Noah (ginzatron):
├── app/                    ├── backend/
├── scripts/                ├── database/
└── CLAUDE.md               └── openspec/
```

Both can touch anything, but primary owner reviews PRs for their area.

## Definition of Done

A feature is DONE when:
- [ ] Code committed and pushed
- [ ] Tests written and passing
- [ ] PR merged (if feature branch)
- [ ] Deployed to /Applications
- [ ] Issue closed
- [ ] Thunderdome shows clean status
