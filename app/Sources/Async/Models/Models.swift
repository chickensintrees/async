import Foundation

// MARK: - Conversation Mode

enum ConversationMode: String, Codable, CaseIterable {
    case anonymous = "anonymous"
    case assisted = "assisted"
    case direct = "direct"

    var displayName: String {
        switch self {
        case .anonymous: return "Anonymous (Agent-Mediated)"
        case .assisted: return "Assisted (With Agent)"
        case .direct: return "Direct (No Agent)"
        }
    }

    var description: String {
        switch self {
        case .anonymous: return "Recipient only sees AI-processed version"
        case .assisted: return "Everyone sees everything, AI can help"
        case .direct: return "Just you and the recipient, no AI"
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
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case githubHandle = "github_handle"
        case displayName = "display_name"
        case email
        case phoneNumber = "phone_number"
        case avatarUrl = "avatar_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

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
}

// MARK: - Conversation

struct Conversation: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let mode: ConversationMode
    let title: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case mode
        case title
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var displayTitle: String {
        title ?? "Conversation"
    }
}

// MARK: - Conversation Participant

struct ConversationParticipant: Codable {
    let conversationId: UUID
    let userId: UUID
    let joinedAt: Date
    let role: String

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case userId = "user_id"
        case joinedAt = "joined_at"
        case role
    }
}

// MARK: - Message

struct Message: Identifiable, Equatable {
    let id: UUID
    let conversationId: UUID
    let senderId: UUID?
    let contentRaw: String
    let contentProcessed: String?
    let isFromAgent: Bool
    let agentContext: String?  // Only used for encoding when sending
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

    // Memberwise init for creating new messages
    init(id: UUID, conversationId: UUID, senderId: UUID?, contentRaw: String,
         contentProcessed: String?, isFromAgent: Bool, agentContext: String?,
         createdAt: Date, processedAt: Date?, rawVisibleTo: [UUID]?) {
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.contentRaw = contentRaw
        self.contentProcessed = contentProcessed
        self.isFromAgent = isFromAgent
        self.agentContext = agentContext
        self.createdAt = createdAt
        self.processedAt = processedAt
        self.rawVisibleTo = rawVisibleTo
    }
}

extension Message: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        conversationId = try container.decode(UUID.self, forKey: .conversationId)
        senderId = try container.decodeIfPresent(UUID.self, forKey: .senderId)
        contentRaw = try container.decode(String.self, forKey: .contentRaw)
        contentProcessed = try container.decodeIfPresent(String.self, forKey: .contentProcessed)
        isFromAgent = try container.decodeIfPresent(Bool.self, forKey: .isFromAgent) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        processedAt = try container.decodeIfPresent(Date.self, forKey: .processedAt)

        // agentContext comes as JSONB - try string first, skip if it's an object
        agentContext = try? container.decodeIfPresent(String.self, forKey: .agentContext)

        // rawVisibleTo is UUID[] - skip for now
        rawVisibleTo = nil
    }
}

extension Message: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(conversationId, forKey: .conversationId)
        try container.encodeIfPresent(senderId, forKey: .senderId)
        try container.encode(contentRaw, forKey: .contentRaw)
        try container.encodeIfPresent(contentProcessed, forKey: .contentProcessed)
        try container.encode(isFromAgent, forKey: .isFromAgent)
        try container.encodeIfPresent(agentContext, forKey: .agentContext)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(processedAt, forKey: .processedAt)
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
