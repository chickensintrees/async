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

struct User: Codable, Identifiable, Equatable {
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
