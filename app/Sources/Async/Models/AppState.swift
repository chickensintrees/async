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
    @Published var isLoading = false
    @Published var errorMessage: String?

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
}
