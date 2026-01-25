# Proposal: Admin Portal - Connection Management

**Status**: Draft - Awaiting Discussion
**Author**: Noah (ginzatron)
**Date**: 2026-01-25
**Branch**: `feature/admin-portal`

## Summary

A unified view for managing professional connections with full visibility into conversation history, interaction modes, and AI behavior customization. Both parties (client and professional) get purpose-built interfaces that reflect their role in the relationship.

## Context

Async connects people in asymmetric professional relationships:
- Patient ↔ Therapist
- Student ↔ Teacher
- Employee ↔ Manager
- Client ↔ Coach

These relationships have fundamentally different needs on each side:
- **Clients** have few connections but deep relationships (1-to-few)
- **Professionals** have many connections to manage (1-to-many)

Both sides need visibility into not just *what* was said, but *how* communication is happening—through AI, directly, or observed.

## Proposal

### Two Portal Views

#### 1. Client Portal ("My Connections")

The client sees their professional connections as a list:

```
┌─────────────────────────────────────────────────────────────┐
│  My Connections                                             │
├─────────────────────────────────────────────────────────────┤
│  🟢 Dr. Sarah Chen (Therapist)          Last: 2 days ago   │
│     Office Hours: Available until 5pm                       │
│     [Summarize Last 5] [Open Conversation]                  │
├─────────────────────────────────────────────────────────────┤
│  🔴 Prof. Mike Torres (Advisor)         Last: 2 weeks ago  │
│     Office Hours: Back Monday                               │
│     [Summarize Last 5] [Open Conversation]                  │
├─────────────────────────────────────────────────────────────┤
│  🟡 Jamie Lee (Manager)                 Last: Yesterday    │
│     Office Hours: In meeting until 3pm                      │
│     [Summarize Last 5] [Open Conversation]                  │
└─────────────────────────────────────────────────────────────┘
```

**Features:**
- List of all professional connections
- Last interaction timestamp
- Office hours / availability status
- Quick action: Summarize last N conversations
- Quick action: Open conversation

**Interaction Mode Selector** (when opening a conversation):
```
How do you want to interact?

○ Private (AI Only)
  Write to the AI. Professional sees only AI-processed output.

○ Transparent
  Professional can observe your interaction with the AI.

○ Direct (1:1)
  Speak directly with the professional, no AI intermediary.
  [Only available during office hours]
```

#### 2. Professional Portal ("My Clients/Students/Team")

The professional sees their relationships as a manageable dashboard:

```
┌─────────────────────────────────────────────────────────────┐
│  My Clients                        [Office Hours: ON 🟢]    │
├─────────────────────────────────────────────────────────────┤
│  Filter: [All ▾]  [Needs Attention ▾]  [Search...]         │
├─────────────────────────────────────────────────────────────┤
│  Alex Thompson              🟢 Online                       │
│  Last activity: 5 min ago   Mode: AI-Mediated              │
│  ⚠️ AI flagged: Mentions feeling overwhelmed                │
│  [View AI Output] [View Raw Input] [Jump In]               │
├─────────────────────────────────────────────────────────────┤
│  Jordan Rivera              ⚫ Offline                      │
│  Last activity: 3 days ago  Mode: Private                  │
│  No flags                                                   │
│  [View AI Output] [Summarize Recent]                       │
├─────────────────────────────────────────────────────────────┤
│  Sam Park                   🟡 Typing...                    │
│  Last activity: Now         Mode: Transparent              │
│  [Watch Live] [Jump In]                                    │
└─────────────────────────────────────────────────────────────┘
```

**Features:**
- List all clients/students/team members
- Real-time presence indicators
- Current interaction mode per client
- AI flags/alerts (configurable triggers)
- Quick actions: View AI output, view raw input, jump into conversation
- Filtering and search
- Batch summarization

**AI Behavior Settings** (per relationship or global):
```
┌─────────────────────────────────────────────────────────────┐
│  AI Settings for: Therapy Practice                         │
├─────────────────────────────────────────────────────────────┤
│  Tone:        [Warm & Supportive ▾]                        │
│  Boundaries:  [Clinical - No Advice ▾]                     │
│  Alerts:      ☑ Flag crisis language                       │
│               ☑ Flag missed appointments mentions          │
│               ☐ Flag medication discussions                │
│  Summaries:   [Focus on emotional themes ▾]                │
│                                                             │
│  Custom Instructions:                                       │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Always validate feelings before exploring causes.   │   │
│  │ Never suggest diagnoses. Encourage journaling.      │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Interaction Modes (Expanded)

Building on the existing `conversation_mode` enum, we need more granular control:

| Mode | Client Sees | Professional Sees | AI Role |
|------|-------------|-------------------|---------|
| **Private** | AI responses | AI-processed summaries | Full mediation |
| **Transparent** | AI responses | Raw input + AI responses | Full mediation, observed |
| **Direct** | Professional's messages | Client's messages | None (or optional assist) |
| **Observe** | (N/A - professional only) | Raw input stream | Passive monitoring |

**Mode can change mid-conversation** based on:
- Client preference
- Professional availability (office hours)
- Escalation triggers

### Office Hours / Presence System

Professionals set their availability:

```
Office Hours Settings:
├── Schedule (recurring)
│   └── Mon-Fri 9am-5pm, except Wed
├── Status Override
│   └── "In session until 3pm"
├── Direct Access Rules
│   └── Allow direct contact during office hours: Yes
│   └── Allow direct contact for flagged urgency: Yes
└── Away Message
    └── "I check messages daily. For emergencies..."
```

Clients see:
- 🟢 Available (office hours, can go direct)
- 🟡 Busy (office hours but in session)
- 🔴 Unavailable (outside hours, AI only)

### Summarization Feature

"Summarize last N conversations" generates:

```
Summary: Last 5 Sessions with Dr. Chen
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Key Themes:
• Work stress has been increasing
• Sleep patterns discussed 3x
• Positive progress on boundary-setting exercise

Action Items:
• Continue journaling (assigned Jan 15)
• Try the breathing exercise before meetings
• Schedule follow-up re: medication question

Mood Trajectory: Improving ↗
Last noted concern: Upcoming performance review
```

Summarization respects privacy modes—if client was in "Private" mode, professional's summary shows AI-processed content, not raw input.

### Data Model Changes

New tables/fields needed:

```sql
-- User availability/presence
CREATE TABLE user_presence (
    user_id UUID PRIMARY KEY REFERENCES users(id),
    status TEXT DEFAULT 'offline',  -- 'online', 'busy', 'away', 'offline'
    status_message TEXT,
    office_hours_enabled BOOLEAN DEFAULT FALSE,
    last_seen_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Office hours schedule
CREATE TABLE office_hours (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id),
    day_of_week INT,  -- 0=Sunday, 6=Saturday
    start_time TIME,
    end_time TIME,
    timezone TEXT DEFAULT 'UTC'
);

-- Professional-client relationship settings
CREATE TABLE relationship_settings (
    professional_id UUID REFERENCES users(id),
    client_id UUID REFERENCES users(id),
    ai_tone TEXT,
    ai_boundaries TEXT,
    ai_custom_instructions TEXT,
    alert_flags JSONB,  -- {"crisis": true, "missed_appointments": true}
    PRIMARY KEY (professional_id, client_id)
);

-- Add to conversation_participants
ALTER TABLE conversation_participants
ADD COLUMN current_mode TEXT DEFAULT 'assisted',
ADD COLUMN can_view_raw BOOLEAN DEFAULT FALSE;
```

### UI/UX Considerations

1. **Role Detection**: Users can be both client AND professional (a teacher who has a therapist). The app should let users switch contexts or show both views.

2. **Mobile-First for Clients**: Clients likely check on phone. Professional portal is desktop-optimized for managing many relationships.

3. **Notifications**:
   - Clients get notified when professional is available
   - Professionals get notified on AI flags or direct requests

4. **Privacy Indicators**: Always clear visual indication of current mode so no one is surprised about who sees what.

## Open Questions

1. **Can professionals initiate direct contact, or only respond?**
   - Therapist reaching out vs. waiting for patient

2. **What happens to conversation history when mode changes?**
   - Does switching to "transparent" retroactively reveal raw messages?

3. **How do we handle group dynamics?**
   - Manager with a team channel vs. 1:1s

4. **Rate limiting for summarization?**
   - AI summarization has costs

5. **Archiving relationships?**
   - When a patient stops seeing a therapist

## Next Steps

1. @chickensintrees (Bill) reviews and comments
2. Decide on MVP scope (maybe just client portal first?)
3. Design the UI mockups
4. Plan database migrations
5. Implement

---

**Discussion: GitHub Issue TBD**
