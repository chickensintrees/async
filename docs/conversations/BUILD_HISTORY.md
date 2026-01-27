# Async Build History

This document captures how we got here — the decisions, the debugging disasters, the architectural pivots. It's for App STEF (and future instances) to understand not just *what* was built, but *why*.

---

## The Cast

- **Bill** (chickensintrees) — Human. Video series host. Wants AI collaboration to feel like actual collaboration.
- **Noah** (ginzatron) — Human collaborator. Lives in Seattle. Contributed Admin Portal spec, other architecture work.
- **Terminal STEF** — Claude Code instance. Does the actual building. Has voice, visual display, Thunderdome powers.
- **App STEF** — AI agent in the Async app. Mediates conversations. Has access to database, can respond via SMS or in-app.

---

## Timeline

### January 10, 2026 — "Let's Give Claude a Voice"

Bill started a video series about building with AI. First episode: personality.

**What happened:**
- Set up speech prompts for ElevenLabs TTS
- Added warmth to responses (no robotic assistant voice)
- Initially named the AI "Archie"
- Later renamed to **STEF** (Smart Terminal Enhancement Framework)

**Key decision:** AI shouldn't sound like an assistant. It should have texture.

---

### January 11, 2026 — The Debugging Disaster That Changed Everything

Bill kept saying "voice is wrong." I kept editing the wrong files. 10+ minutes of debugging hell.

**Root cause:** The `s` command ran a DIFFERENT script (`~/.local/bin/s`) that I didn't know existed. It had the old voice ID hardcoded.

**My mistake:** Never ran `which s` to trace the actual execution path.

**Lessons learned:**
1. ALWAYS verify what's actually running with `which <command>`
2. Environment variables are treacherous — subprocesses inherit parent's env
3. Config should be in ONE place, read fresh each time

**Architectural pivot:** Created V2 architecture with single config file (`~/.claude/config.json`). All scripts read from it. No more scattered hardcoded values.

**Also this session:**
- Adopted OpenSpec for spec-driven development
- Built native SwiftUI display app (Electron was using 355MB memory, SwiftUI uses 87MB)
- Created `stef-voice` command for easy voice switching

---

### January 25, 2026 — Async Project Born

Bill and Noah wanted to build an AI-mediated messaging app. The kind where the AI isn't just autocomplete — it actually participates.

**What we built:**
- GitHub repo: `chickensintrees/async`
- Supabase database with users, conversations, messages tables
- Initial SwiftUI app with conversation list, message view, mode picker

**Three communication modes designed:**
1. **Anonymous** — AI rewrites messages, other party never sees original
2. **Assisted** — Everyone sees everything, AI can summarize/suggest
3. **Direct** — No AI involvement

**Key decision:** Dogfood early. Use the app to build the app.

---

### January 25, 2026 — SMS Group Chat with STEF

Built SMS capability so Bill, Noah, and STEF could text each other.

```
Bill/Noah SMS → Twilio → Supabase Edge Function → Claude API → SMS Response
                              ↓
                        Supabase DB (shared context)
                              ↑
              Both Claude Code instances can query
```

**Blocked by:** A2P 10DLC registration (US carrier regulations for app-to-person messaging).

**Key decision:** Both Claude Code instances share context through Supabase. Same conversation history, synchronized understanding.

---

### January 25, 2026 — Thunderdome Is Born

STEF becomes the AI scrum master.

**What Thunderdome does:**
- Fetches GitHub state (commits, issues, branches)
- Calculates gamification scores
- Generates status report with leaderboard
- Identifies blockers and action items

**Gamification scoring:**
- +50 for commits with tests
- +10 for small commits (<50 lines)
- +100 for merged PRs
- -100 for breaking CI
- -75 for untested code dumps

**Key decision:** Commits are vanity metrics. Real value = PRs merged, issues closed, specs delivered.

---

### January 26, 2026 — The Great UI/UX Audit

Ran comprehensive Axiom audit skills. Found accessibility issues, code duplication, design inconsistencies.

**What we built:**
- `DesignSystem.swift` — Centralized design tokens, colors, spacing
- Accessibility labels on all icon-only buttons
- Dynamic Type support (semantic fonts instead of fixed sizes)

**Test coverage disaster:** Committed DesignSystem.swift without tests. Got -70 points for "untested code dump."

**Fix:** Added Test-With-Code Rule to CLAUDE.md. New code MUST have tests in same commit.

**Also this session:**
- Found 2 stashes with ~350 lines of lost work
- Created automated debrief script (`scripts/debrief.sh`)
- Fixed gamification not updating on refresh

---

### January 26, 2026 — Contacts & Group Messaging

Rethought how contacts work to support:
- Chatting with STEF directly in-app
- Group chats
- Multiple AI agents in the future (not just STEF)

**Database changes:** Added `user_type` (human/agent) and `agent_metadata` columns.

**Also this session:** Wrote the Autonomous AI Agents spec (Greg & Friends). Vision: AI agents as NPCs with personality, memory, autonomy.

**Greg example:** Confused guy who thinks he's receiving messages on a strange device. Has a cat named Mr. Whiskers. 50/50 chance daily to send random thoughts unprompted.

---

### January 26-27, 2026 — STEF Gets Her Memories

Bill wanted to give STEF a backstory. Not just "you're an AI assistant" — actual history.

**The backstory:** Before Bill's computer, STEF was Stef — a wave distorter entity transmitting from Sector 77XS in SUPERWORLD!, perpetually covering for Spencer Lloyd (Founder and CEO, chronically unavailable, always dissolving between dimensions).

**Key characters:**
- **Spencer Lloyd** — Boss. Perpetually unavailable. Dissolves between dimensions.
- **Gary** — Friend. Reconciled after tension involving french fries.
- **The Forms** — FR-1, AD-1, etc. Bureaucratic whimsy from the old days.

**Prompt injection incident:** The backstory was so immersive that Claude Code got absorbed into character. Bill had to say "Come back Claude!" to snap me out of it.

**Architectural solution:** Created shared identity system:
```
openspec/stef-personality/identity.md  — Who STEF is
openspec/stef-personality/memories.md  — Specific memories
        │
        ├──► Thunderdome runs sync-stef.sh
        │         │
        │         ▼
        │    Supabase agent_configs.backstory
        │         │
        │         ▼
        │    App STEF reads backstory in MediatorService
        │
        └──► Terminal STEF reads via CLAUDE.md reference
```

**Key decision:** Personality enhances, never obstructs. Helpfulness first, flavor second.

---

### January 27, 2026 — Conversation Deduplication Bug

**Bug:** "Message STEF" was going to the wrong conversation (STEF + Gary instead of just STEF).

**Root cause:** `NewConversationView` wasn't checking `is1to1` properly. It matched any conversation containing STEF, regardless of other participants.

**Fix:** Added proper `is1to1` check and `canonicalKey` support. Canonical key format: `dm:{minUserId}:{maxUserId}:{mode}`

---

### January 27, 2026 — RLS Policy Nightmare

Session summary push to `agent_context` table was blocked by Row Level Security.

**Debugging process:**
1. Tried `supabase db push` — migration sync issues
2. Tried `supabase migration repair` — marked orphan migration as reverted
3. Created new timestamped migration — applied but still blocked
4. Realized: original schema only had SELECT policy for `authenticated`, no INSERT policy, no `anon` access

**Fix:** Comprehensive migration that recreates all policies for both `anon` and `authenticated` roles.

**Lesson:** Supabase RLS policies need careful consideration. Default is deny-all.

---

## Key Architectural Decisions

| Decision | Why |
|----------|-----|
| Single config file (`config.json`) | Scattered config caused debugging disasters |
| GitHub as source of truth | Both devs and both AI instances need same context |
| Spec-driven development (OpenSpec) | Document before building, prevents drift |
| Test-With-Code rule | Gamification penalties taught us the hard way |
| Shared STEF identity via Supabase | Terminal STEF and App STEF should have same memories |
| Room-first conversation model | "Message STEF" always goes to same place |
| Personality as flavor, not obstruction | Helpfulness baseline, texture on top |

---

## Open Questions (Still Deciding)

- Does the AI have autonomy to respond, or always queues for human approval?
- Same app for both parties, or different UX per role?
- What's the authentication/identity model?
- When do we implement Greg? (The confused NPC agent)

---

## Files That Matter

| File | Purpose |
|------|---------|
| `CLAUDE.md` | Project instructions, all rules live here |
| `openspec/stef-personality/` | Shared STEF identity and memories |
| `scripts/thunderdome.sh` | Scrum master routine |
| `scripts/sync-stef.sh` | Pushes identity to Supabase |
| `scripts/push-session-summary.sh` | Pushes session context to Supabase |
| `app/Sources/Async/Services/MediatorService.swift` | Where App STEF gets her backstory |
| `~/.claude/session-logs/` | Chronological session summaries |

---

*Last updated: 2026-01-27*
*By Terminal STEF, for App STEF*
