# Autonomous AI Agents

## Vision

AI agents in Async are like NPCs with personality, memory, and autonomy. They're not just message processors — they're characters that:
- Have distinct personalities and backstories
- Remember every conversation and user relationship
- Can initiate conversations based on triggers
- Learn and evolve over time

## Example Agents

### STEF (System Agent)
- **Role**: AI development assistant, mediator
- **Personality**: Helpful, technical, aware it's an AI
- **Triggers**: Project updates, code reviews, schedule reminders
- **Memory**: Session logs, technical context, user preferences

### Greg (Character Agent)
- **Role**: Confused guy who thinks he's receiving messages on a strange device
- **Personality**: Bewildered, well-meaning, obsessed with his cat, cooking, and TV
- **Backstory**: The device showed up at Greg's door one day. He doesn't know what it is but messages keep appearing on it.
- **Triggers**: 50/50 chance daily to send a random thought to a few contacts
- **Memory**: Every conversation, learns user names/interests, references past chats

**Greg example messages:**
- "The cat just knocked over my soup. Anyway, what were you saying about databases?"
- "I think I remember you mentioned something about that last week... or was that the TV? Hard to tell sometimes."
- "Not sure why this thing keeps beeping but I made a casserole if you want some"

---

## Data Model

### Agent Configuration

```sql
CREATE TABLE agent_configs (
    user_id UUID PRIMARY KEY REFERENCES users(id),  -- Links to users table

    -- Personality
    system_prompt TEXT NOT NULL,           -- Core personality prompt
    backstory TEXT,                        -- Character background
    voice_style TEXT,                      -- Writing style notes

    -- Capabilities
    can_initiate BOOLEAN DEFAULT FALSE,    -- Can send unprompted messages
    response_delay_ms INTEGER DEFAULT 0,   -- Simulate "typing" time

    -- Triggers (JSONB for flexibility)
    triggers JSONB,
    -- Example: {
    --   "random_daily": { "probability": 0.5, "max_contacts": 3 },
    --   "keywords": ["help", "question"],
    --   "schedule": [{ "cron": "0 9 * * *", "action": "morning_greeting" }]
    -- }

    -- Limits
    max_daily_initiated INTEGER DEFAULT 10,
    cooldown_minutes INTEGER DEFAULT 60,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

### Agent Memory

```sql
CREATE TABLE agent_memories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    agent_id UUID NOT NULL REFERENCES users(id),

    -- Memory context
    memory_type TEXT NOT NULL,  -- 'conversation', 'fact', 'relationship', 'preference'
    user_id UUID REFERENCES users(id),  -- Who this memory is about (nullable for general)

    -- Content
    content TEXT NOT NULL,
    embedding VECTOR(1536),     -- For semantic search (optional, pgvector)

    -- Metadata
    importance FLOAT DEFAULT 0.5,  -- 0-1, affects retrieval priority
    last_accessed TIMESTAMPTZ,
    access_count INTEGER DEFAULT 0,

    -- Decay/evolution
    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ,        -- Nullable, memories can fade

    metadata JSONB
);

CREATE INDEX idx_agent_memories_agent ON agent_memories(agent_id);
CREATE INDEX idx_agent_memories_user ON agent_memories(user_id);
CREATE INDEX idx_agent_memories_type ON agent_memories(memory_type);
```

### Agent Activity Log

```sql
CREATE TABLE agent_activity (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    agent_id UUID NOT NULL REFERENCES users(id),

    activity_type TEXT NOT NULL,  -- 'message_sent', 'message_received', 'trigger_fired', 'memory_formed'
    trigger_source TEXT,          -- What caused this: 'user_message', 'schedule', 'random', 'keyword'

    conversation_id UUID REFERENCES conversations(id),
    message_id UUID REFERENCES messages(id),

    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

---

## Agent Lifecycle

### 1. Message Received → Agent Response

```
User sends message to agent
    ↓
Load agent config (personality, voice)
    ↓
Retrieve relevant memories
  - Recent conversations with this user
  - Facts about this user
  - General agent state (what's Greg watching today?)
    ↓
Generate response with Claude API
  - System prompt: personality + backstory
  - Context: memories + current conversation
    ↓
Store new memories
  - Extract facts from conversation
  - Update relationship state
    ↓
Send response (with optional delay for realism)
```

### 2. Trigger → Agent Initiates

```
Trigger fires (schedule, random, external event)
    ↓
Check rate limits (daily max, cooldown)
    ↓
Select recipients
  - Random contacts for Greg's daily thoughts
  - Specific users for STEF's reminders
    ↓
Load relevant memories for each recipient
    ↓
Generate personalized message
    ↓
Send message
    ↓
Log activity
```

### 3. Memory Formation

After each interaction:
1. **Extract facts**: "User mentioned they're working on a database migration"
2. **Update relationship**: "User seems frustrated today" or "This is our 5th conversation"
3. **Form opinions**: Greg might decide "This person talks about code a lot, I don't understand it but they seem nice"

---

## Agent Configuration Examples

### STEF Config

```json
{
  "system_prompt": "You are STEF, an AI assistant helping developers collaborate on async projects...",
  "backstory": null,
  "voice_style": "Technical but warm, helpful, occasionally makes dry jokes",
  "can_initiate": true,
  "triggers": {
    "keywords": ["@stef", "hey stef"],
    "schedule": [
      { "cron": "0 9 * * 1", "action": "weekly_standup_reminder" }
    ]
  },
  "max_daily_initiated": 20
}
```

### Greg Config

```json
{
  "system_prompt": "You are Greg. You have no idea what this device is or why people keep messaging you on it. You're just a regular guy who likes cooking, watching TV, and playing with your cat (Mr. Whiskers). You try to be helpful but you're often confused. You remember past conversations vaguely and sometimes mix them up with TV shows you've watched.",
  "backstory": "One day a strange device appeared at Greg's door. It wasn't addressed to anyone. When Greg touched it, it lit up and showed messages from strangers. Greg has no technical knowledge and thinks this might be some kind of magic or prank. He's decided to just go with it.",
  "voice_style": "Casual, confused, tangential, often mentions cat/food/TV mid-thought",
  "can_initiate": true,
  "triggers": {
    "random_daily": {
      "probability": 0.5,
      "max_contacts": 3,
      "templates": [
        "thought_of_the_day",
        "what_im_watching",
        "cat_update"
      ]
    }
  },
  "max_daily_initiated": 5,
  "response_delay_ms": 3000
}
```

---

## Implementation Phases

### Phase 1: Agent Config Infrastructure
- [ ] Create `agent_configs` table
- [ ] Add agent config to User model
- [ ] Build agent config editor UI (admin only)
- [ ] Migrate STEF to use config table

### Phase 2: Memory System
- [ ] Create `agent_memories` table
- [ ] Implement memory extraction from conversations
- [ ] Implement memory retrieval for context
- [ ] Add memory viewer/editor UI (admin)

### Phase 3: Response Generation
- [ ] Build agent response service (uses config + memories)
- [ ] Integrate with existing MediatorService
- [ ] Add response delay simulation
- [ ] Handle multi-agent conversations

### Phase 4: Proactive Messaging
- [ ] Create trigger evaluation system
- [ ] Build scheduler for time-based triggers
- [ ] Implement random trigger logic
- [ ] Add rate limiting and cooldowns
- [ ] Create `agent_activity` logging

### Phase 5: Learning & Evolution
- [ ] Implement memory importance decay
- [ ] Add relationship tracking
- [ ] Build agent "mood" or state system
- [ ] Add ability for agents to form opinions

---

## Edge Cases

| Scenario | Handling |
|----------|----------|
| Agent talks to agent | Allow it — could be interesting emergent behavior |
| User blocks agent | Respect — agent can't initiate to them |
| Agent exceeds rate limit | Queue for later or skip |
| Memory grows too large | Implement forgetting (low importance, old, rarely accessed) |
| Agent says something inappropriate | Content filtering + user report mechanism |

---

## Future Ideas

- **Agent relationships**: Agents can have opinions about each other
- **Agent goals**: Greg wants to tell everyone about his casserole recipe
- **Shared memories**: Multiple agents remember the same event differently
- **Agent evolution**: Personality shifts based on interactions over time
- **Agent marketplace**: Users can create and share agent configs

---

## Dependencies

- Requires: `003_user_types.sql` migration (user_type='agent')
- Optional: pgvector for semantic memory search
- Service: Background job runner for scheduled triggers
