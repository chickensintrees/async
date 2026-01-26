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
        if let title = title, !title.isEmpty {
            return title
        }
        // Generate a fallback based on mode and date
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return "\(mode.displayName) - \(formatter.string(from: createdAt))"
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
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(conversation.id)
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
