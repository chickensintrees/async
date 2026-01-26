import SwiftUI
import Supabase

enum FilterMode {
    case all, unread
}

enum AppTab: String, CaseIterable {
    case messages = "Messages"
    case contacts = "Contacts"
    case dashboard = "Dashboard"
    case backlog = "Backlog"

    var icon: String {
        switch self {
        case .messages: return "message.fill"
        case .contacts: return "person.2.fill"
        case .dashboard: return "chart.bar.fill"
        case .backlog: return "list.bullet.rectangle"
        }
    }
}

@MainActor
class AppState: ObservableObject {
    @Published var selectedTab: AppTab = .messages
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
                    phoneNumber: nil,
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

    // MARK: - Contact Management

    func loadAllUsers() async -> [User] {
        do {
            let users: [User] = try await supabase
                .from("users")
                .select()
                .order("display_name", ascending: true)
                .execute()
                .value
            return users
        } catch {
            errorMessage = "Failed to load contacts: \(error.localizedDescription)"
            return []
        }
    }

    func createUser(displayName: String, githubHandle: String?, phoneNumber: String?, email: String?) async -> User? {
        do {
            let newUser = User(
                id: UUID(),
                githubHandle: githubHandle,
                displayName: displayName,
                email: email,
                phoneNumber: phoneNumber,
                avatarUrl: nil,
                createdAt: Date(),
                updatedAt: Date()
            )

            try await supabase
                .from("users")
                .insert(newUser)
                .execute()

            return newUser
        } catch {
            errorMessage = "Failed to create contact: \(error.localizedDescription)"
            return nil
        }
    }

    func updateUser(id: UUID, displayName: String, githubHandle: String?, phoneNumber: String?, email: String?) async -> User? {
        do {
            let updates = UserUpdate(
                displayName: displayName,
                githubHandle: githubHandle,
                phoneNumber: phoneNumber,
                email: email,
                updatedAt: Date()
            )

            try await supabase
                .from("users")
                .update(updates)
                .eq("id", value: id.uuidString)
                .execute()

            // Fetch updated user
            let users: [User] = try await supabase
                .from("users")
                .select()
                .eq("id", value: id.uuidString)
                .execute()
                .value

            return users.first
        } catch {
            errorMessage = "Failed to update contact: \(error.localizedDescription)"
            print("Update error: \(error)")
            return nil
        }
    }

    func deleteUser(_ id: UUID) async {
        do {
            try await supabase
                .from("users")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
        } catch {
            errorMessage = "Failed to delete contact: \(error.localizedDescription)"
        }
    }
}

// Helper struct for user updates
struct UserUpdate: Encodable {
    let displayName: String
    let githubHandle: String?
    let phoneNumber: String?
    let email: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case githubHandle = "github_handle"
        case phoneNumber = "phone_number"
        case email
        case updatedAt = "updated_at"
    }
}
