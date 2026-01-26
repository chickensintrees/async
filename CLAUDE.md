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

Once MVP is working, chickensintrees and ginzatron will use Async to coordinate development of Async itself. This gives us:
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
├── dashboard/          # GitHub monitoring dashboard (SwiftUI)
│   ├── Package.swift
│   ├── Sources/AsyncDashboard.swift
│   └── scripts/        # start-dashboard.sh, install.sh
├── scripts/
│   └── sms-context.sh  # Query shared SMS conversation for Claude Code sync
├── backend/
│   ├── database/
│   │   ├── schema.sql              # Core database schema
│   │   └── migrations/             # Database migrations
│   │       └── 001_sms_support.sql # SMS/Twilio support
│   └── supabase/
│       └── functions/
│           └── sms-webhook/        # Twilio webhook Edge Function
└── app/                # SwiftUI application (future)
```

## Dashboard (Live)

A native macOS app for monitoring the repo and tracking developer contributions.

### Running the Dashboard
```bash
cd dashboard
./scripts/install.sh      # First time only
./scripts/start-dashboard.sh
```

### Features
- **Activity Feed**: Real-time repo events (commits, issues, PRs)
- **Leaderboard**: Competitive scoring between chickensintrees and ginzatron
- **AI Commentary**: Claude-powered trash talk via "Request Fresh Roast" button

### Gamification Scoring
| Action | Points |
|--------|--------|
| Commit with tests | +50 |
| Small commit (<50 lines) | +10 |
| PR merged | +100 |
| **Breaking CI** | **-100** |
| Untested code dump (>300 lines) | -75 |
| Lazy commit message | -15 |

### Titles (Score-Based)
- 0-99: Keyboard Polisher
- 100-299: Bug Whisperer
- 1000-1999: Pull Request Paladin
- 4000-7499: Test Titan
- 15000+: Code Demigod

### Shame Titles
- "Build Breaker" - 3+ CI failures
- "YOLO Developer" - No tests in 5+ commits
- "Benchwarmer" - Lowest weekly score

## Development Workflow

### Spec-Driven Development
1. **Check specs first** - Before implementing, read relevant specs in `openspec/specs/`
2. **Propose changes** - Create a change folder in `openspec/changes/` before coding
3. **Implement to spec** - Follow all SHALL/MUST requirements
4. **Update specs** - Archive completed changes to specs/

### Collaboration
- chickensintrees and ginzatron are collaborating on this project
- Use GitHub Issues for discussion and tracking
- PRs require review before merge
- Major decisions documented in openspec/

## AI-Managed Code Review & Merging

**IMPORTANT FOR ALL CLAUDE CODE INSTANCES**: The AI (STEF/Claude) manages all code review and merging for this project. This applies whether you're working with chickensintrees or ginzatron.

### Branch Strategy
- `main` - Production-ready code
- `feature/*` - Feature branches (e.g., `feature/admin-portal`)
- All feature work happens on branches, merged via PR

### Workflow for BOTH Contributors

#### When Your Human Writes Code:
1. **Create a feature branch** if working on something substantial
   ```bash
   git checkout -b feature/your-feature-name
   ```
2. **Commit with good messages** (affects gamification score!)
3. **Push to origin** when ready for review
   ```bash
   git push -u origin feature/your-feature-name
   ```
4. **Tell the AI to create a PR** or create one yourself

#### When AI Reviews Code:
The AI (you, reading this) should:
1. **Fetch the PR/branch**
   ```bash
   gh pr list
   gh pr view <number>
   gh pr diff <number>
   ```
2. **Review for**:
   - Code quality and style consistency
   - Test coverage (remember: untested code = negative points!)
   - Security issues (OWASP top 10)
   - Spec compliance (check `openspec/specs/`)
3. **Leave comments** on the PR
   ```bash
   gh pr comment <number> --body "Review comments here"
   ```
4. **Approve or request changes**
   ```bash
   gh pr review <number> --approve --body "LGTM"
   gh pr review <number> --request-changes --body "Please fix X"
   ```

#### When AI Merges Code:
Once approved:
```bash
# Merge with merge commit (preserves history)
gh pr merge <number> --merge

# Or squash (cleaner history for small PRs)
gh pr merge <number> --squash

# Delete the branch after merge
gh pr merge <number> --merge --delete-branch
```

### Conflict Resolution
If there are merge conflicts:
1. **Notify the human** about the conflict
2. **Fetch latest main** into the feature branch
   ```bash
   git fetch origin
   git checkout feature/branch-name
   git merge origin/main
   ```
3. **Resolve conflicts** (with human guidance if needed)
4. **Push the resolution**
5. **Complete the merge**

### Cross-Contributor Sync
When chickensintrees pushes to main and ginzatron has a feature branch (or vice versa):
1. AI should **proactively check for divergence**
2. **Notify the other contributor** if their branch is behind
3. **Suggest rebasing or merging** main into their branch

### PR Checklist (AI Should Verify)
- [ ] Code compiles/builds
- [ ] Tests pass (run `swift test` for app/)
- [ ] No secrets committed
- [ ] Commit messages are descriptive
- [ ] Related issue linked (if applicable)
- [ ] Spec updated (if behavior changed)

## Protocol Thunderdome (Scrum Master Routine)

STEF acts as AI scrum master for this project. When chickensintrees says **"Protocol Thunderdome"** or **"run scrum"**, execute this routine:

### 1. Fetch Current State
```bash
# Recent commits (all contributors)
gh api repos/chickensintrees/async/commits --jq '.[:15] | .[] | "\(.sha[0:7]) \(.author.login): \(.commit.message | split("\n")[0])"'

# Recent activity
gh api repos/chickensintrees/async/events --jq '.[:10] | .[] | "\(.created_at | split("T")[0]) \(.actor.login): \(.type)"'

# Open issues
gh api repos/chickensintrees/async/issues --jq '.[] | "#\(.number) [\(.state)] \(.title)"'

# Latest comments
gh api repos/chickensintrees/async/issues/comments --jq '.[-5:] | .[] | "Issue #\(.issue_url | split("/") | last) - \(.user.login): \(.body | split("\n")[0])"'

# Check all branches for contributor activity
gh api repos/chickensintrees/async/branches --jq '.[].name'
```

### 2. Calculate Scores
Using the gamification scoring system:
- +50 for commits with tests
- +10 for small commits (<50 lines)
- +100 for merged PRs
- -100 for breaking CI
- -75 for untested code dumps (>300 lines)
- -15 for lazy commit messages

### 3. Generate Report
Output a status report with:
- **Leaderboard** - Scores and titles for chickensintrees & ginzatron
- **Recent Activity** - Who did what
- **Backlog** - Prioritized issue list
- **Blockers** - Anything blocking progress
- **Recommended Actions** - Next steps

### 4. Identify Action Items
- Specs needing review
- PRs waiting for merge
- Issues needing response
- Tests to write

## Design Principles

1. **AI as intermediary, not replacement** - The AI enhances communication, doesn't replace human connection
2. **Async-first** - Not trying to be real-time chat; embrace the asynchronous nature
3. **Privacy-conscious** - Messages contain sensitive content; design for trust
4. **Native experience** - SwiftUI for polished macOS feel
5. **Dogfood early** - Use the tool to build the tool

## SMS Group Chat (STEF Integration)

Bill and Noah can communicate via SMS with STEF as a participant. Both Claude Code instances share context through Supabase.

### How It Works
1. SMS messages go to Twilio → Edge Function → Supabase
2. When @STEF is mentioned, Claude API generates a response
3. Response sent back via Twilio SMS to all participants
4. Both Bill's and Noah's Claude Code can query the shared conversation

### Sync Context (For Claude Code)
```bash
./scripts/sms-context.sh      # Fetch last 50 messages
./scripts/sms-context.sh 100  # Fetch last 100 messages
```

### Trigger STEF Response
- `@stef` or `stef` (as a word)
- `@claude`
- `hey stef`

### Setup
See `backend/supabase/functions/sms-webhook/README.md` for full setup instructions.

## Open Questions

- [x] Database choice - **Supabase (Postgres)** ✓
- [x] First feature to build - **SMS Group Chat with STEF** ✓
- [ ] Does the AI have autonomy to respond, or always queues for human approval?
- [ ] Same app for both parties, or different UX per role?
- [ ] What's the authentication/identity model?
