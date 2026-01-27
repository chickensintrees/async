import Foundation
import SwiftUI

// MARK: - User Type

enum UserType: String, Codable, CaseIterable {
    case human = "human"
    case agent = "agent"

    var icon: String {
        switch self {
        case .human: return "person.fill"
        case .agent: return "sparkles"
        }
    }

    var badgeColor: Color {
        switch self {
        case .human: return .clear
        case .agent: return .purple
        }
    }
}

// MARK: - Agent Metadata

struct AgentMetadata: Codable, Equatable, Hashable {
    let provider: String?
    let model: String?
    let capabilities: [String]?
    let isSystem: Bool?

    enum CodingKeys: String, CodingKey {
        case provider, model, capabilities
        case isSystem = "is_system"
    }

    init(provider: String? = nil, model: String? = nil, capabilities: [String]? = nil, isSystem: Bool? = nil) {
        self.provider = provider
        self.model = model
        self.capabilities = capabilities
        self.isSystem = isSystem
    }
}

// MARK: - Agent Model Selection

enum AgentModel: String, Codable, CaseIterable {
    case sonnet = "claude-sonnet-4-20250514"
    case opus = "claude-opus-4-5-20251101"
    case haiku = "claude-3-5-haiku-20241022"

    var displayName: String {
        switch self {
        case .sonnet: return "Sonnet 4"
        case .opus: return "Opus 4.5"
        case .haiku: return "Haiku 3.5"
        }
    }

    var description: String {
        switch self {
        case .sonnet: return "Balanced speed and intelligence"
        case .opus: return "Most capable, best for complex tasks"
        case .haiku: return "Fastest responses, lower cost"
        }
    }
}

// MARK: - Agent Knowledge Base

struct AgentKnowledgeBase: Codable, Equatable {
    var documents: [String]?
    var context: String?
    var examples: [String]?

    init(documents: [String]? = nil, context: String? = nil, examples: [String]? = nil) {
        self.documents = documents
        self.context = context
        self.examples = examples
    }
}

// MARK: - Agent Memory (Persistent Context)

/// Represents a memory/fact that an agent has learned from conversations
struct AgentMemory: Codable, Identifiable {
    let id: UUID
    let contextType: String  // 'fact', 'decision', 'interaction', 'summary'
    let title: String
    let content: String
    let participants: [String]?  // Agent/user IDs involved
    let createdAt: Date
    let metadata: [String: String]?  // Source conversation, confidence, etc.

    enum CodingKeys: String, CodingKey {
        case id
        case contextType = "context_type"
        case title
        case content
        case participants
        case createdAt = "created_at"
        case metadata
    }

    init(id: UUID = UUID(), contextType: String, title: String, content: String,
         participants: [String]? = nil, createdAt: Date = Date(), metadata: [String: String]? = nil) {
        self.id = id
        self.contextType = contextType
        self.title = title
        self.content = content
        self.participants = participants
        self.createdAt = createdAt
        self.metadata = metadata
    }
}

// MARK: - Cross-Conversation Context (for agent memory across conversations)

/// Context from another conversation for cross-conversation agent memory
struct CrossConversationContext: Codable, Identifiable {
    let conversationId: UUID
    let conversationTitle: String?
    let participantNames: [String]
    let recentMessages: [CrossConversationMessage]
    let lastActivityAt: Date

    var id: UUID { conversationId }

    /// Brief summary for the agent prompt
    var promptSummary: String {
        let participants = participantNames.isEmpty ? "Unknown" : participantNames.joined(separator: ", ")
        let title = conversationTitle ?? "Conversation with \(participants)"
        return "[\(title)] - \(recentMessages.count) recent messages"
    }
}

/// A message from another conversation (for cross-conversation context)
struct CrossConversationMessage: Codable {
    let senderName: String
    let content: String
    let timestamp: Date
    let isFromAgent: Bool
}

// MARK: - Agent Config

struct AgentConfig: Codable, Identifiable {
    let userId: UUID
    var systemPrompt: String
    var backstory: String?
    var voiceStyle: String?
    var canInitiate: Bool
    var responseDelayMs: Int?
    // Note: triggers is JSONB in DB but not used yet in app
    // Skip decoding to avoid type mismatch errors
    var maxDailyInitiated: Int?
    var cooldownMinutes: Int?

    // Extended fields (migration 006)
    var model: String
    var temperature: Double
    var knowledgeBase: AgentKnowledgeBase?
    var isPublic: Bool
    var createdBy: UUID?
    var description: String?
    var avatarUrl: String?

    let createdAt: Date
    var updatedAt: Date

    var id: UUID { userId }

    /// Computed property to get/set model as enum
    var modelEnum: AgentModel {
        get { AgentModel(rawValue: model) ?? .sonnet }
        set { model = newValue.rawValue }
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case systemPrompt = "system_prompt"
        case backstory
        case voiceStyle = "voice_style"
        case canInitiate = "can_initiate"
        case responseDelayMs = "response_delay_ms"
        // Note: triggers excluded - it's JSONB in DB, skipped for now
        case maxDailyInitiated = "max_daily_initiated"
        case cooldownMinutes = "cooldown_minutes"
        case model
        case temperature
        case knowledgeBase = "knowledge_base"
        case isPublic = "is_public"
        case createdBy = "created_by"
        case description
        case avatarUrl = "avatar_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(UUID.self, forKey: .userId)
        systemPrompt = try container.decode(String.self, forKey: .systemPrompt)
        backstory = try container.decodeIfPresent(String.self, forKey: .backstory)
        voiceStyle = try container.decodeIfPresent(String.self, forKey: .voiceStyle)
        canInitiate = try container.decodeIfPresent(Bool.self, forKey: .canInitiate) ?? false
        responseDelayMs = try container.decodeIfPresent(Int.self, forKey: .responseDelayMs)
        // Skip triggers - it's JSONB in DB, not used yet in app
        maxDailyInitiated = try container.decodeIfPresent(Int.self, forKey: .maxDailyInitiated)
        cooldownMinutes = try container.decodeIfPresent(Int.self, forKey: .cooldownMinutes)
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? AgentModel.sonnet.rawValue
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.7
        knowledgeBase = try container.decodeIfPresent(AgentKnowledgeBase.self, forKey: .knowledgeBase)
        isPublic = try container.decodeIfPresent(Bool.self, forKey: .isPublic) ?? true
        createdBy = try container.decodeIfPresent(UUID.self, forKey: .createdBy)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    init(userId: UUID, systemPrompt: String, backstory: String? = nil, voiceStyle: String? = nil,
         canInitiate: Bool = false, responseDelayMs: Int? = nil,
         maxDailyInitiated: Int? = nil, cooldownMinutes: Int? = nil, model: String = AgentModel.sonnet.rawValue,
         temperature: Double = 0.7, knowledgeBase: AgentKnowledgeBase? = nil, isPublic: Bool = true,
         createdBy: UUID? = nil, description: String? = nil, avatarUrl: String? = nil,
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.userId = userId
        self.systemPrompt = systemPrompt
        self.backstory = backstory
        self.voiceStyle = voiceStyle
        self.canInitiate = canInitiate
        self.responseDelayMs = responseDelayMs
        self.maxDailyInitiated = maxDailyInitiated
        self.cooldownMinutes = cooldownMinutes
        self.model = model
        self.temperature = temperature
        self.knowledgeBase = knowledgeBase
        self.isPublic = isPublic
        self.createdBy = createdBy
        self.description = description
        self.avatarUrl = avatarUrl
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Conversation Kind

enum ConversationKind: String, Codable, CaseIterable {
    case direct1to1 = "direct_1to1"
    case directGroup = "direct_group"
    case channel = "channel"
    case system = "system"

    var displayName: String {
        switch self {
        case .direct1to1: return "Direct Message"
        case .directGroup: return "Group"
        case .channel: return "Channel"
        case .system: return "System"
        }
    }
}

// MARK: - Conversation Mode

enum ConversationMode: String, Codable, CaseIterable {
    case anonymous = "anonymous"
    case assisted = "assisted"
    case direct = "direct"

    var displayName: String {
        switch self {
        case .anonymous: return "Mediated"
        case .assisted: return "Enhanced"
        case .direct: return "Direct"
        }
    }

    var description: String {
        switch self {
        case .anonymous: return "AI rewrites your message professionally"
        case .assisted: return "Your message + AI summaries"
        case .direct: return "Your exact words, no AI"
        }
    }
}

// MARK: - User

struct User: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var githubHandle: String?
    var displayName: String
    var email: String?
    var phoneNumber: String?
    var avatarUrl: String?
    var userType: UserType
    var agentMetadata: AgentMetadata?
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case githubHandle = "github_handle"
        case displayName = "display_name"
        case email
        case phoneNumber = "phone_number"
        case avatarUrl = "avatar_url"
        case userType = "user_type"
        case agentMetadata = "agent_metadata"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // MARK: - Computed Properties

    var isAgent: Bool { userType == .agent }
    var isHuman: Bool { userType == .human }
    var isSystemAgent: Bool { agentMetadata?.isSystem == true }

    var formattedPhone: String? {
        guard let phone = phoneNumber else { return nil }
        // Format: +1 (412) 512-3593
        if phone.count == 12 && phone.hasPrefix("+1") {
            let area = phone.dropFirst(2).prefix(3)
            let first = phone.dropFirst(5).prefix(3)
            let last = phone.suffix(4)
            return "+1 (\(area)) \(first)-\(last)"
        }
        return phone
    }

    var capabilitiesDescription: String? {
        guard let caps = agentMetadata?.capabilities, !caps.isEmpty else { return nil }
        return caps.joined(separator: " \u{2022} ")
    }

    // MARK: - Initializers

    init(id: UUID, githubHandle: String? = nil, displayName: String, email: String? = nil,
         phoneNumber: String? = nil, avatarUrl: String? = nil, userType: UserType = .human,
         agentMetadata: AgentMetadata? = nil, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.githubHandle = githubHandle
        self.displayName = displayName
        self.email = email
        self.phoneNumber = phoneNumber
        self.avatarUrl = avatarUrl
        self.userType = userType
        self.agentMetadata = agentMetadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        githubHandle = try container.decodeIfPresent(String.self, forKey: .githubHandle)
        displayName = try container.decode(String.self, forKey: .displayName)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        // Default to human if not present (backward compatibility)
        userType = try container.decodeIfPresent(UserType.self, forKey: .userType) ?? .human
        agentMetadata = try container.decodeIfPresent(AgentMetadata.self, forKey: .agentMetadata)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

// MARK: - Conversation

struct Conversation: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let mode: ConversationMode
    let kind: ConversationKind
    let title: String?
    let topic: String?
    let canonicalKey: String?
    let lastMessageAt: Date?
    let isPrivate: Bool  // When true, agents can't access from other conversations
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case mode
        case kind
        case title
        case topic
        case canonicalKey = "canonical_key"
        case lastMessageAt = "last_message_at"
        case isPrivate = "is_private"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var displayTitle: String {
        if let title = title, !title.isEmpty {
            return title
        }
        // Generate a fallback based on mode and date
        return "\(mode.displayName) - \(Formatters.shortDate.string(from: createdAt))"
    }

    /// Whether this is a 1:1 direct message
    var is1to1: Bool { kind == .direct1to1 }

    /// Whether this is a group conversation
    var isGroup: Bool { kind == .directGroup || kind == .channel }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        mode = try container.decode(ConversationMode.self, forKey: .mode)
        // Default to directGroup for backward compatibility
        kind = try container.decodeIfPresent(ConversationKind.self, forKey: .kind) ?? .directGroup
        title = try container.decodeIfPresent(String.self, forKey: .title)
        topic = try container.decodeIfPresent(String.self, forKey: .topic)
        canonicalKey = try container.decodeIfPresent(String.self, forKey: .canonicalKey)
        lastMessageAt = try container.decodeIfPresent(Date.self, forKey: .lastMessageAt)
        // Default to false - agents can access unless explicitly private
        isPrivate = try container.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    init(id: UUID, mode: ConversationMode, kind: ConversationKind = .directGroup,
         title: String? = nil, topic: String? = nil, canonicalKey: String? = nil,
         lastMessageAt: Date? = nil, isPrivate: Bool = false,
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.mode = mode
        self.kind = kind
        self.title = title
        self.topic = topic
        self.canonicalKey = canonicalKey
        self.lastMessageAt = lastMessageAt
        self.isPrivate = isPrivate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Conversation with Details (for display)

struct ConversationWithDetails: Identifiable, Equatable, Hashable {
    let conversation: Conversation
    let participants: [User]
    let lastMessage: Message?
    let unreadCount: Int

    var id: UUID { conversation.id }

    /// Display title: participant names or custom title
    var displayTitle: String {
        if let title = conversation.title, !title.isEmpty {
            return title
        }
        // Show other participants' names (exclude current user shown elsewhere)
        let names = participants.map { $0.displayName }
        if names.isEmpty {
            return "New Conversation"
        }
        return names.joined(separator: ", ")
    }

    /// Last message preview (truncated)
    var lastMessagePreview: String? {
        guard let msg = lastMessage else { return nil }
        let content = msg.contentRaw
        if content.count > 50 {
            return String(content.prefix(47)) + "..."
        }
        return content
    }

    /// Relative timestamp for last activity
    var relativeTime: String {
        let date = lastMessage?.createdAt ?? conversation.updatedAt
        let now = Date()
        let diff = now.timeIntervalSince(date)

        if diff < 60 {
            return "now"
        } else if diff < 3600 {
            let mins = Int(diff / 60)
            return "\(mins)m"
        } else if diff < 86400 {
            let hours = Int(diff / 3600)
            return "\(hours)h"
        } else if diff < 604800 {
            let days = Int(diff / 86400)
            return "\(days)d"
        } else {
            return Formatters.monthDay.string(from: date)
        }
    }

    // Hash and equality only by conversation ID so List selection stays stable
    // when other properties change (lastMessage, unreadCount, participants)
    func hash(into hasher: inout Hasher) {
        hasher.combine(conversation.id)
    }

    static func == (lhs: ConversationWithDetails, rhs: ConversationWithDetails) -> Bool {
        lhs.conversation.id == rhs.conversation.id
    }
}

// MARK: - Conversation Participant

struct ConversationParticipant: Codable {
    let conversationId: UUID
    let userId: UUID
    let joinedAt: Date
    let role: String
    var isMuted: Bool
    var isArchived: Bool
    var lastReadMessageId: UUID?

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case userId = "user_id"
        case joinedAt = "joined_at"
        case role
        case isMuted = "is_muted"
        case isArchived = "is_archived"
        case lastReadMessageId = "last_read_message_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        conversationId = try container.decode(UUID.self, forKey: .conversationId)
        userId = try container.decode(UUID.self, forKey: .userId)
        joinedAt = try container.decode(Date.self, forKey: .joinedAt)
        role = try container.decode(String.self, forKey: .role)
        // Default values for backward compatibility
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        lastReadMessageId = try container.decodeIfPresent(UUID.self, forKey: .lastReadMessageId)
    }

    init(conversationId: UUID, userId: UUID, joinedAt: Date = Date(), role: String = "member",
         isMuted: Bool = false, isArchived: Bool = false, lastReadMessageId: UUID? = nil) {
        self.conversationId = conversationId
        self.userId = userId
        self.joinedAt = joinedAt
        self.role = role
        self.isMuted = isMuted
        self.isArchived = isArchived
        self.lastReadMessageId = lastReadMessageId
    }
}

// MARK: - Message

struct Message: Codable, Identifiable, Equatable {
    let id: UUID
    let conversationId: UUID
    let senderId: UUID?
    let contentRaw: String
    let contentProcessed: String?
    let isFromAgent: Bool
    let agentContext: String?  // JSON string
    let createdAt: Date
    let processedAt: Date?
    let rawVisibleTo: [UUID]?

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case contentRaw = "content_raw"
        case contentProcessed = "content_processed"
        case isFromAgent = "is_from_agent"
        case agentContext = "agent_context"
        case createdAt = "created_at"
        case processedAt = "processed_at"
        case rawVisibleTo = "raw_visible_to"
    }

    /// Returns the content to display based on conversation mode and viewer
    func displayContent(for viewerId: UUID?, mode: ConversationMode) -> String {
        switch mode {
        case .direct:
            return contentRaw
        case .assisted:
            // Show both raw and processed if available
            if let processed = contentProcessed {
                return "\(contentRaw)\n\n📝 AI Summary: \(processed)"
            }
            return contentRaw
        case .anonymous:
            // Only show processed if viewer shouldn't see raw
            if let visibleTo = rawVisibleTo, let viewer = viewerId, visibleTo.contains(viewer) {
                return contentRaw
            }
            return contentProcessed ?? contentRaw
        }
    }
}

// MARK: - Message Read

struct MessageRead: Codable {
    let messageId: UUID
    let userId: UUID
    let readAt: Date

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case userId = "user_id"
        case readAt = "read_at"
    }
}

// MARK: - Connection Status

enum ConnectionStatus: String, Codable, CaseIterable {
    case pending = "pending"
    case active = "active"
    case paused = "paused"
    case declined = "declined"
    case archived = "archived"

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .active: return "Active"
        case .paused: return "Paused"
        case .declined: return "Declined"
        case .archived: return "Archived"
        }
    }

    var color: String {
        switch self {
        case .pending: return "orange"
        case .active: return "green"
        case .paused: return "yellow"
        case .declined: return "red"
        case .archived: return "gray"
        }
    }
}

// MARK: - Connection

struct Connection: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let ownerId: UUID
    let subscriberId: UUID
    var status: ConnectionStatus
    let requestMessage: String?
    let statusChangedAt: Date
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case subscriberId = "subscriber_id"
        case status
        case requestMessage = "request_message"
        case statusChangedAt = "status_changed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Tag

struct Tag: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let ownerId: UUID
    var name: String
    var color: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case name
        case color
        case createdAt = "created_at"
    }
}

// MARK: - Connection Tag (Junction)

struct ConnectionTag: Codable, Equatable {
    let connectionId: UUID
    let tagId: UUID
    let assignedAt: Date

    enum CodingKeys: String, CodingKey {
        case connectionId = "connection_id"
        case tagId = "tag_id"
        case assignedAt = "assigned_at"
    }
}

// MARK: - Connection with User (for display)

struct ConnectionWithUser: Identifiable, Equatable, Hashable {
    let connection: Connection
    let user: User  // The other party (subscriber for owner view, owner for subscriber view)
    var tags: [Tag]

    var id: UUID { connection.id }

    func hash(into hasher: inout Hasher) {
        hasher.combine(connection.id)
    }
}
