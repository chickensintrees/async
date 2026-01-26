# Contacts & Group Messaging Rearchitecture

## Problem Statement

Current limitations:
1. **No way to chat with STEF** in the app (only via SMS)
2. **No group chat creation UI** (backend supports it, UI doesn't)
3. **Contacts and conversations are disconnected** — you manage contacts separately, but create conversations by GitHub handle lookup
4. **No visual distinction** between humans and AI agents

Future requirement: Multiple AI agents (not just STEF) should be first-class participants.

## Solution Overview

1. Add `user_type` column to distinguish humans from agents
2. Replace single-user conversation creation with multi-select participant picker
3. Update ContactsView with sectioned display (Agents / People)
4. Add mode-specific rules for agent inclusion

---

## Database Changes

### Migration: `003_user_types.sql`

```sql
-- Add user_type column (human vs agent)
ALTER TABLE users ADD COLUMN user_type TEXT NOT NULL DEFAULT 'human';

-- Add agent-specific metadata
ALTER TABLE users ADD COLUMN agent_metadata JSONB;
-- Example: {"provider": "anthropic", "model": "claude-3", "capabilities": ["mediation"], "is_system": true}

-- Index for efficient queries
CREATE INDEX idx_users_user_type ON users(user_type);

-- Constraint for valid types
ALTER TABLE users ADD CONSTRAINT check_user_type CHECK (user_type IN ('human', 'agent'));

-- Update STEF to be an agent
UPDATE users
SET user_type = 'agent',
    agent_metadata = '{"provider":"anthropic","model":"claude-3","capabilities":["mediation","summarization","context-aware"],"is_system":true}'::jsonb
WHERE id = '00000000-0000-0000-0000-000000000001';
```

---

## Model Changes

### `Models.swift`

```swift
enum UserType: String, Codable, CaseIterable {
    case human = "human"
    case agent = "agent"
}

struct AgentMetadata: Codable, Equatable {
    let provider: String?
    let model: String?
    let capabilities: [String]?
    let isSystem: Bool?

    enum CodingKeys: String, CodingKey {
        case provider, model, capabilities
        case isSystem = "is_system"
    }
}

// Add to User struct:
var userType: UserType  // defaults to .human for existing records
var agentMetadata: AgentMetadata?

// Computed helpers:
var isAgent: Bool { userType == .agent }
var isHuman: Bool { userType == .human }
var isSystemAgent: Bool { agentMetadata?.isSystem == true }
```

---

## UI Changes

### 1. ContactsView — Sectioned Display

- **AI Agents** section at top (purple gradient avatars, sparkles icon)
- **People** section below (existing contact rows)
- Toggle to show/hide agents
- Prevent deletion of system agents (STEF)

### 2. NewConversationView — Multi-Select Participant Picker

**Replace current flow (GitHub handle lookup → single user) with:**

1. Search bar (filters by name or handle)
2. Scrollable contact list with checkboxes
   - Agents section first
   - People section below
3. Selected participants shown as chips (removable)
4. Title field (optional)
5. Mode picker with smart defaults

**Mode-Aware Logic:**

| Mode | Agent Behavior |
|------|----------------|
| Direct | Agents excluded (warning if selected) |
| Assisted | Agents optional, can participate |
| Anonymous | Agent required (auto-add STEF if none selected) |

### 3. Visual Design — Agent Identity

| Element | Human | AI Agent |
|---------|-------|----------|
| Avatar | Solid color from name hash | Purple-blue gradient |
| Avatar icon | First initial | Sparkles |
| Badge | None | Purple CPU badge (bottom-right) |
| System label | None | "SYSTEM" tag |

---

## Files to Modify

| File | Changes |
|------|---------|
| `backend/database/migrations/003_user_types.sql` | **New** — Migration |
| `app/Sources/Async/Models/Models.swift` | Add `UserType`, `AgentMetadata`, update `User` |
| `app/Sources/Async/Views/ContactsView.swift` | Section by type, agent badges |
| `app/Sources/Async/Views/NewConversationView.swift` | Multi-select picker |
| `app/Sources/Async/Models/AppState.swift` | Add `loadAllUsers(includeAgents:)`, `loadAgents()` |

**New UI Components:**
- `ParticipantSelectRow` — Checkbox row for multi-select
- `ParticipantChip` — Selected participant chip
- `AgentBadge` — Purple CPU overlay badge

---

## Edge Cases

| Scenario | Handling |
|----------|----------|
| Delete STEF | Prevent — system agents can't be deleted |
| Only self selected | Error: "Add at least one other participant" |
| Anonymous with no human recipient | Error: "Anonymous mode requires at least one human recipient" |
| Agent-only conversation | Warning shown, allowed (future multi-agent use case) |
| Direct mode with agent selected | Auto-remove agents, show warning |

---

## Future Hooks (Not in This Story)

- **Connection-based permissions** — Limit who you can create groups with
- **Agent-specific permissions** — Rate limits, capability restrictions
- **Per-agent settings** — Custom instructions per agent

---

## Verification

1. **Database**: Run migration, verify STEF has `user_type='agent'`
2. **Contacts**: Open app, see STEF in "AI Agents" section with purple avatar
3. **New Conversation**: Create conversation, multi-select Bill + Noah + STEF
4. **Mode Logic**: Select Direct mode → STEF auto-removed with warning
5. **Group Chat**: Verify messages show correctly for all participants
6. **SMS**: Verify SMS integration still works with existing STEF user

---

## Acceptance Criteria

- [ ] STEF appears as a contact in the app
- [ ] Can create 1:1 chat with STEF directly from app
- [ ] Can create group chat with multiple humans + agents
- [ ] Agents visually distinguished from humans
- [ ] Mode-specific agent rules enforced
- [ ] Existing SMS functionality preserved
