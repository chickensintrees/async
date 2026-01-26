import SwiftUI
import Supabase

enum FilterMode {
    case all, unread
}

@MainActor
class AppState: ObservableObject {
    @Published var currentUser: User?
    @Published var conversations: [Conversation] = []
    @Published var selectedConversation: Conversation?
    @Published var messages: [Message] = []
    @Published var filterMode: FilterMode = .all
    @Published var showNewConversation = false
    @Published var showHelp = false
    @Published var showAdminPortal = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Admin Portal state
    @Published var subscribers: [ConnectionWithUser] = []
    @Published var subscriptions: [ConnectionWithUser] = []
    @Published var tags: [Tag] = []
    @Published var selectedConnection: ConnectionWithUser?

    private let supabase: SupabaseClient

    init() {
        // Initialize Supabase client
        self.supabase = SupabaseClient(
            supabaseURL: URL(string: Config.supabaseURL)!,
            supabaseKey: Config.supabaseAnonKey
        )
    }

    // MARK: - User Management

    func loadOrCreateUser(githubHandle: String, displayName: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Try to find existing user
            let existing: [User] = try await supabase
                .from("users")
                .select()
                .eq("github_handle", value: githubHandle)
                .execute()
                .value

            if let user = existing.first {
                self.currentUser = user
            } else {
                // Create new user
                let newUser = User(
                    id: UUID(),
                    githubHandle: githubHandle,
                    displayName: displayName,
                    email: nil,
                    avatarUrl: nil,
                    createdAt: Date(),
                    updatedAt: Date()
                )

                try await supabase
                    .from("users")
                    .insert(newUser)
                    .execute()

                self.currentUser = newUser
            }
        } catch {
            errorMessage = "Failed to load user: \(error.localizedDescription)"
        }
    }

    // MARK: - Conversations

    func loadConversations() async {
        guard let user = currentUser else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            // Get conversation IDs for this user
            let participations: [ConversationParticipant] = try await supabase
                .from("conversation_participants")
                .select()
                .eq("user_id", value: user.id.uuidString)
                .execute()
                .value

            let conversationIds = participations.map { $0.conversationId.uuidString }

            if !conversationIds.isEmpty {
                let convos: [Conversation] = try await supabase
                    .from("conversations")
                    .select()
                    .in("id", values: conversationIds)
                    .order("updated_at", ascending: false)
                    .execute()
                    .value

                self.conversations = convos
            }
        } catch {
            errorMessage = "Failed to load conversations: \(error.localizedDescription)"
        }
    }

    func createConversation(with participantIds: [UUID], mode: ConversationMode, title: String?) async -> Conversation? {
        guard let user = currentUser else { return nil }
        isLoading = true
        defer { isLoading = false }

        do {
            // Create conversation
            let conversation = Conversation(
                id: UUID(),
                mode: mode,
                title: title,
                createdAt: Date(),
                updatedAt: Date()
            )

            try await supabase
                .from("conversations")
                .insert(conversation)
                .execute()

            // Add participants (including current user)
            var allParticipants = participantIds
            if !allParticipants.contains(user.id) {
                allParticipants.append(user.id)
            }

            for participantId in allParticipants {
                let participant = ConversationParticipant(
                    conversationId: conversation.id,
                    userId: participantId,
                    joinedAt: Date(),
                    role: participantId == user.id ? "admin" : "member"
                )

                try await supabase
                    .from("conversation_participants")
                    .insert(participant)
                    .execute()
            }

            await loadConversations()
            return conversation
        } catch {
            errorMessage = "Failed to create conversation: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Messages

    func loadMessages(for conversation: Conversation) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let msgs: [Message] = try await supabase
                .from("messages")
                .select()
                .eq("conversation_id", value: conversation.id.uuidString)
                .order("created_at", ascending: true)
                .execute()
                .value

            self.messages = msgs
        } catch {
            errorMessage = "Failed to load messages: \(error.localizedDescription)"
        }
    }

    func sendMessage(content: String, to conversation: Conversation) async {
        guard let user = currentUser else { return }

        do {
            let message = Message(
                id: UUID(),
                conversationId: conversation.id,
                senderId: user.id,
                contentRaw: content,
                contentProcessed: nil,  // AI will process this
                isFromAgent: false,
                agentContext: nil,
                createdAt: Date(),
                processedAt: nil,
                rawVisibleTo: nil
            )

            try await supabase
                .from("messages")
                .insert(message)
                .execute()

            // Reload messages
            await loadMessages(for: conversation)

            // TODO: Trigger AI processing based on conversation mode
        } catch {
            errorMessage = "Failed to send message: \(error.localizedDescription)"
        }
    }

    // MARK: - Users lookup

    func findUser(byGithubHandle handle: String) async -> User? {
        do {
            let users: [User] = try await supabase
                .from("users")
                .select()
                .eq("github_handle", value: handle)
                .execute()
                .value

            return users.first
        } catch {
            return nil
        }
    }

    // MARK: - Connections (Admin Portal)

    /// Load all subscribers (people subscribed TO the current user)
    func loadSubscribers() async {
        guard let user = currentUser else { return }

        do {
            let connections: [Connection] = try await supabase
                .from("connections")
                .select()
                .eq("owner_id", value: user.id.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value

            // Load user info and tags for each connection
            var result: [ConnectionWithUser] = []
            for connection in connections {
                if let subscriber = await loadUser(byId: connection.subscriberId) {
                    let connectionTags = await loadTagsForConnection(connection.id)
                    result.append(ConnectionWithUser(
                        connection: connection,
                        user: subscriber,
                        tags: connectionTags
                    ))
                }
            }
            self.subscribers = result
        } catch {
            errorMessage = "Failed to load subscribers: \(error.localizedDescription)"
        }
    }

    /// Load all subscriptions (people the current user is subscribed TO)
    func loadSubscriptions() async {
        guard let user = currentUser else { return }

        do {
            let connections: [Connection] = try await supabase
                .from("connections")
                .select()
                .eq("subscriber_id", value: user.id.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value

            // Load user info for each connection
            var result: [ConnectionWithUser] = []
            for connection in connections {
                if let owner = await loadUser(byId: connection.ownerId) {
                    result.append(ConnectionWithUser(
                        connection: connection,
                        user: owner,
                        tags: []  // Subscribers don't see tags
                    ))
                }
            }
            self.subscriptions = result
        } catch {
            errorMessage = "Failed to load subscriptions: \(error.localizedDescription)"
        }
    }

    /// Helper to load a user by ID
    private func loadUser(byId id: UUID) async -> User? {
        do {
            let users: [User] = try await supabase
                .from("users")
                .select()
                .eq("id", value: id.uuidString)
                .execute()
                .value
            return users.first
        } catch {
            return nil
        }
    }

    /// Create a subscription request (current user subscribes to another user)
    func createSubscription(toUserId: UUID, message: String?) async -> Bool {
        guard let user = currentUser else { return false }

        do {
            let connection = Connection(
                id: UUID(),
                ownerId: toUserId,
                subscriberId: user.id,
                status: .pending,
                requestMessage: message,
                statusChangedAt: Date(),
                createdAt: Date(),
                updatedAt: Date()
            )

            try await supabase
                .from("connections")
                .insert(connection)
                .execute()

            await loadSubscriptions()
            return true
        } catch {
            errorMessage = "Failed to create subscription: \(error.localizedDescription)"
            return false
        }
    }

    /// Update connection status (owner approves, declines, etc.)
    func updateConnectionStatus(_ connectionId: UUID, to status: ConnectionStatus) async {
        do {
            try await supabase
                .from("connections")
                .update(["status": status.rawValue, "status_changed_at": ISO8601DateFormatter().string(from: Date())])
                .eq("id", value: connectionId.uuidString)
                .execute()

            await loadSubscribers()
        } catch {
            errorMessage = "Failed to update connection: \(error.localizedDescription)"
        }
    }

    /// Cancel a pending subscription request
    func cancelSubscription(_ connectionId: UUID) async {
        do {
            try await supabase
                .from("connections")
                .delete()
                .eq("id", value: connectionId.uuidString)
                .execute()

            await loadSubscriptions()
        } catch {
            errorMessage = "Failed to cancel subscription: \(error.localizedDescription)"
        }
    }

    // MARK: - Tags

    /// Load all tags for the current user
    func loadTags() async {
        guard let user = currentUser else { return }

        do {
            let userTags: [Tag] = try await supabase
                .from("tags")
                .select()
                .eq("owner_id", value: user.id.uuidString)
                .order("name", ascending: true)
                .execute()
                .value

            self.tags = userTags
        } catch {
            errorMessage = "Failed to load tags: \(error.localizedDescription)"
        }
    }

    /// Load tags assigned to a specific connection
    private func loadTagsForConnection(_ connectionId: UUID) async -> [Tag] {
        do {
            let connectionTags: [ConnectionTag] = try await supabase
                .from("connection_tags")
                .select()
                .eq("connection_id", value: connectionId.uuidString)
                .execute()
                .value

            let tagIds = connectionTags.map { $0.tagId.uuidString }
            if tagIds.isEmpty { return [] }

            let tags: [Tag] = try await supabase
                .from("tags")
                .select()
                .in("id", values: tagIds)
                .execute()
                .value

            return tags
        } catch {
            return []
        }
    }

    /// Create a new tag
    func createTag(name: String, color: String) async -> Tag? {
        guard let user = currentUser else { return nil }

        do {
            let tag = Tag(
                id: UUID(),
                ownerId: user.id,
                name: name,
                color: color,
                createdAt: Date()
            )

            try await supabase
                .from("tags")
                .insert(tag)
                .execute()

            await loadTags()
            return tag
        } catch {
            errorMessage = "Failed to create tag: \(error.localizedDescription)"
            return nil
        }
    }

    /// Update a tag
    func updateTag(_ tagId: UUID, name: String, color: String) async {
        do {
            try await supabase
                .from("tags")
                .update(["name": name, "color": color])
                .eq("id", value: tagId.uuidString)
                .execute()

            await loadTags()
            await loadSubscribers()  // Refresh to show updated tag names
        } catch {
            errorMessage = "Failed to update tag: \(error.localizedDescription)"
        }
    }

    /// Delete a tag
    func deleteTag(_ tagId: UUID) async {
        do {
            try await supabase
                .from("tags")
                .delete()
                .eq("id", value: tagId.uuidString)
                .execute()

            await loadTags()
            await loadSubscribers()  // Refresh to remove deleted tag from connections
        } catch {
            errorMessage = "Failed to delete tag: \(error.localizedDescription)"
        }
    }

    /// Assign a tag to a connection
    func assignTag(_ tagId: UUID, toConnection connectionId: UUID) async {
        do {
            let connectionTag = ConnectionTag(
                connectionId: connectionId,
                tagId: tagId,
                assignedAt: Date()
            )

            try await supabase
                .from("connection_tags")
                .insert(connectionTag)
                .execute()

            await loadSubscribers()
        } catch {
            errorMessage = "Failed to assign tag: \(error.localizedDescription)"
        }
    }

    /// Remove a tag from a connection
    func removeTag(_ tagId: UUID, fromConnection connectionId: UUID) async {
        do {
            try await supabase
                .from("connection_tags")
                .delete()
                .eq("connection_id", value: connectionId.uuidString)
                .eq("tag_id", value: tagId.uuidString)
                .execute()

            await loadSubscribers()
        } catch {
            errorMessage = "Failed to remove tag: \(error.localizedDescription)"
        }
    }
}
