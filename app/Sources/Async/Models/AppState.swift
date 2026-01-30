import SwiftUI
import Supabase
import Realtime

// File-based debug logging for memory system (Swift print() doesn't show when app runs)
func memoryLog(_ source: String, _ message: String) {
    // Use /tmp since app might be sandboxed and can't write to home directory
    let logPath = URL(fileURLWithPath: "/tmp/async-memory-debug.log")
    let timestamp = Formatters.iso8601Now()
    let line = "[\(source)][\(timestamp)] \(message)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logPath.path) {
            if let handle = try? FileHandle(forWritingTo: logPath) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: logPath)
        }
    }
}

enum FilterMode {
    case all, unread
}

enum AppTab: String, CaseIterable {
    case messages = "Messages"
    case contacts = "Contacts"
    case training = "Training"
    case dashboard = "Dashboard"
    case backlog = "Backlog"
    case admin = "Admin"

    var icon: String {
        switch self {
        case .messages: return "message.fill"
        case .contacts: return "person.2.fill"
        case .training: return "brain.head.profile"
        case .dashboard: return "chart.bar.fill"
        case .backlog: return "list.bullet.rectangle"
        case .admin: return "gearshape.2.fill"
        }
    }
}

@MainActor
class AppState: ObservableObject {
    // Well-known agent IDs
    static let stefAgentId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let terminalStefId = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    // Agents that should NOT auto-respond via in-app Claude API
    // (Terminal STEF is controlled by Claude Code, not the app)
    static let externalAgentIds: Set<UUID> = [terminalStefId]

    @Published var selectedTab: AppTab = .messages
    @Published var currentUser: User?
    @Published var conversations: [ConversationWithDetails] = []
    @Published var selectedConversation: ConversationWithDetails?
    @Published var messages: [Message] = []
    @Published var filterMode: FilterMode = .all
    @Published var showNewConversation = false
    @Published var showHelp = false
    @Published var showAdminPortal = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Memory system: track previous conversation for extraction on exit
    private var previousConversationId: UUID?
    private var previousMessages: [Message] = []
    private var previousParticipants: [User] = []

    // Admin Portal state
    @Published var subscribers: [ConnectionWithUser] = []
    @Published var subscriptions: [ConnectionWithUser] = []
    @Published var tags: [Tag] = []
    @Published var selectedConnection: ConnectionWithUser?

    /// Pending GitHub actions from agent responses, keyed by message ID
    @Published var pendingActions: [UUID: [GitHubAction]] = [:]

    // Realtime subscription for autonomous agent responses
    private var realtimeTask: Task<Void, Never>?
    private var recentlyRespondedMessages: Set<UUID> = []  // Debounce
    private let responseDebounceSeconds: TimeInterval = 5.0

    private let supabase: SupabaseClient

    init() {
        // Initialize Supabase client
        self.supabase = SupabaseClient(
            supabaseURL: URL(string: Config.supabaseURL)!,
            supabaseKey: Config.supabaseAnonKey
        )
    }

    // MARK: - Realtime Subscription for Autonomous Agent Responses

    /// Start listening for messages that @mention App STEF across all conversations
    func startRealtimeSubscription() {
        guard realtimeTask == nil else {
            memoryLog("Realtime", "Subscription already active")
            return
        }

        memoryLog("Realtime", "Starting message subscription...")

        realtimeTask = Task {
            let channel = supabase.channel("app-stef-mentions")

            let insertions = channel.postgresChange(
                InsertAction.self,
                schema: "public",
                table: "messages"
            )

            do {
                try await channel.subscribeWithError()
                memoryLog("Realtime", "✅ Subscribed to messages table")
            } catch {
                memoryLog("Realtime", "❌ Subscription failed: \(error)")
                return
            }

            memoryLog("Realtime", "Waiting for messages...")
            for await insertion in insertions {
                memoryLog("Realtime", "📨 Got insertion event")
                await handleNewMessage(insertion.record)
            }
            memoryLog("Realtime", "Loop ended (should not happen)")
        }
    }

    /// Stop the realtime subscription
    func stopRealtimeSubscription() {
        realtimeTask?.cancel()
        realtimeTask = nil
        print("🔔 [Realtime] Subscription stopped")
    }

    /// Handle a new message from realtime subscription
    private func handleNewMessage(_ record: [String: AnyJSON]) async {
        memoryLog("Realtime", "handleNewMessage called with record keys: \(record.keys.joined(separator: ", "))")

        // Extract message details from the record
        guard let messageIdStr = record["id"]?.stringValue,
              let messageId = UUID(uuidString: messageIdStr),
              let conversationIdStr = record["conversation_id"]?.stringValue,
              let conversationId = UUID(uuidString: conversationIdStr),
              let senderIdStr = record["sender_id"]?.stringValue,
              let senderId = UUID(uuidString: senderIdStr),
              let content = record["content_raw"]?.stringValue else {
            memoryLog("Realtime", "❌ Could not parse message record")
            // Log what we got for debugging
            for (key, value) in record {
                memoryLog("Realtime", "  \(key): \(value)")
            }
            return
        }

        let isFromAgent = record["is_from_agent"]?.boolValue ?? false

        memoryLog("Realtime", "New message: \(content.prefix(50))... from \(senderIdStr.prefix(8))")

        // Skip if we already responded to this message (debounce)
        if recentlyRespondedMessages.contains(messageId) {
            memoryLog("Realtime", "Already responded to \(messageId), skipping")
            return
        }

        // Skip messages from App STEF herself (prevent loops)
        if senderId == AppState.stefAgentId {
            memoryLog("Realtime", "Message from self, skipping")
            return
        }

        // Note: We respond even in the active conversation because STEF should
        // always respond to @mentions. The user will see the response appear naturally.

        // Check if this is an auto-respond conversation (like Green Room) OR if STEF is @mentioned
        let isAutoRespondConversation = KnownConversation.autoRespondConversations.contains(conversationId)

        // Check if App STEF is @mentioned
        let stefUser = User(
            id: AppState.stefAgentId,
            githubHandle: "stef-ai",
            displayName: "STEF",
            email: nil,
            phoneNumber: nil,
            userType: .agent,
            createdAt: Date()
        )

        let isMentioned = MediatorService.shared.isAgentMentioned(stefUser, in: content)

        guard isMentioned || isAutoRespondConversation else {
            memoryLog("Realtime", "STEF not @mentioned and not auto-respond conv: \(content.prefix(50)), skipping")
            return
        }

        if isAutoRespondConversation {
            memoryLog("Realtime", "✅ Auto-respond conversation (Green Room)! Generating response...")
        } else {
            memoryLog("Realtime", "✅ STEF @mentioned! Generating autonomous response...")
        }

        // Mark as responded (debounce)
        recentlyRespondedMessages.insert(messageId)

        // Clean up old debounce entries after a delay
        Task {
            try? await Task.sleep(nanoseconds: UInt64(responseDebounceSeconds * 1_000_000_000))
            recentlyRespondedMessages.remove(messageId)
        }

        // Load conversation and generate response
        await generateAutonomousResponse(
            toMessageContent: content,
            inConversationId: conversationId,
            fromSenderId: senderId,
            isFromAgent: isFromAgent
        )
    }

    /// Generate an autonomous response when App STEF is @mentioned
    private func generateAutonomousResponse(
        toMessageContent content: String,
        inConversationId conversationId: UUID,
        fromSenderId senderId: UUID,
        isFromAgent: Bool
    ) async {
        // Load conversation details
        guard let conversation = await loadConversation(byId: conversationId) else {
            print("🔔 [Realtime] Could not load conversation \(conversationId)")
            return
        }

        let conversationDetails = await loadConversationDetails(conversation, currentUserId: AppState.stefAgentId)

        // Get sender name
        let sender = await loadUser(byId: senderId)
        let senderName = sender?.displayName ?? (isFromAgent ? "Agent" : "User")

        // Load STEF as agent
        guard let stefAgent = await loadUser(byId: AppState.stefAgentId) else {
            print("🔔 [Realtime] Could not load STEF agent")
            return
        }

        let allAgents = await loadAgents()

        print("🔔 [Realtime] Generating response to '\(content.prefix(30))...' from \(senderName)")

        // Generate and send response
        await generateAndSendAgentResponse(
            agent: stefAgent,
            userMessage: content,
            senderName: senderName,
            conversation: conversation,
            conversationDetails: conversationDetails,
            allAgents: allAgents,
            depth: 0
        )

        print("🔔 [Realtime] Autonomous response sent!")
    }

    // MARK: - Login/Logout (Simple Test Auth)

    var isLoggedIn: Bool {
        currentUser != nil
    }

    func loginAsUser(githubHandle: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let users: [User] = try await supabase
                .from("users")
                .select()
                .eq("github_handle", value: githubHandle)
                .execute()
                .value

            if let user = users.first {
                self.currentUser = user
                await loadConversations()
                startRealtimeSubscription()  // Enable autonomous agent responses
                print("✓ Logged in as: \(user.displayName) (@\(user.githubHandle ?? "unknown"))")
            } else {
                errorMessage = "User not found: @\(githubHandle)"
            }
        } catch {
            errorMessage = "Login failed: \(error.localizedDescription)"
        }
    }

    func logout() {
        stopRealtimeSubscription()  // Clean up autonomous responses
        currentUser = nil
        conversations = []
        selectedConversation = nil
        messages = []
        print("✓ Logged out")
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
                // Create new human user
                let newUser = User(
                    id: UUID(),
                    githubHandle: githubHandle,
                    displayName: displayName,
                    email: nil,
                    phoneNumber: nil,
                    avatarUrl: nil,
                    userType: .human,
                    agentMetadata: nil,
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

                // Load details for each conversation
                var result: [ConversationWithDetails] = []
                for convo in convos {
                    let details = await loadConversationDetails(convo, currentUserId: user.id)
                    result.append(details)
                }
                print("📋 [LOAD] Loaded \(result.count) conversations")
                print("📋 [LOAD] Selected before: \(selectedConversation?.conversation.id.uuidString ?? "nil")")
                self.conversations = result
                print("📋 [LOAD] Selected after: \(selectedConversation?.conversation.id.uuidString ?? "nil")")
            }
        } catch {
            errorMessage = "Failed to load conversations: \(error.localizedDescription)"
        }
    }

    /// Load participants and last message for a conversation
    private func loadConversationDetails(_ conversation: Conversation, currentUserId: UUID) async -> ConversationWithDetails {
        var participants: [User] = []
        var lastMessage: Message? = nil

        do {
            // Get all participants
            let parts: [ConversationParticipant] = try await supabase
                .from("conversation_participants")
                .select()
                .eq("conversation_id", value: conversation.id.uuidString)
                .execute()
                .value

            // Load user info for participants (excluding current user)
            for part in parts where part.userId != currentUserId {
                if let user = await loadUser(byId: part.userId) {
                    participants.append(user)
                }
            }

            // Get last message
            let msgs: [Message] = try await supabase
                .from("messages")
                .select()
                .eq("conversation_id", value: conversation.id.uuidString)
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value

            lastMessage = msgs.first
        } catch {
            // Silently fail - we'll show conversation without details
        }

        return ConversationWithDetails(
            conversation: conversation,
            participants: participants,
            lastMessage: lastMessage,
            unreadCount: 0  // TODO: implement unread tracking
        )
    }

    func createConversation(with participantIds: [UUID], mode: ConversationMode, title: String?) async -> ConversationWithDetails? {
        guard let user = currentUser else { return nil }
        isLoading = true
        defer { isLoading = false }

        do {
            // Determine all participants (including current user)
            var allParticipants = participantIds
            if !allParticipants.contains(user.id) {
                allParticipants.append(user.id)
            }

            // Determine conversation kind based on participant count
            let kind: ConversationKind = allParticipants.count == 2 ? .direct1to1 : .directGroup

            // Generate canonical key for 1:1 conversations (ensures no duplicates)
            var canonicalKey: String? = nil
            if kind == .direct1to1 {
                let sortedIds = allParticipants.map { $0.uuidString }.sorted()
                canonicalKey = "dm:\(sortedIds[0]):\(sortedIds[1]):\(mode.rawValue)"
            }

            // Check database for existing conversation with same canonical key
            // This handles cases where local state is stale but DB has the conversation
            if let canonicalKey = canonicalKey {
                let existing: [Conversation] = try await supabase
                    .from("conversations")
                    .select()
                    .eq("canonical_key", value: canonicalKey)
                    .limit(1)
                    .execute()
                    .value

                if let existingConvo = existing.first {
                    print("📋 [CREATE] Found existing conversation with canonical_key: \(canonicalKey)")
                    // Ensure current user is a participant (they might not be if this is a reused key)
                    let parts: [ConversationParticipant] = try await supabase
                        .from("conversation_participants")
                        .select()
                        .eq("conversation_id", value: existingConvo.id.uuidString)
                        .eq("user_id", value: user.id.uuidString)
                        .execute()
                        .value

                    if parts.isEmpty {
                        // Add current user as participant
                        let participant = ConversationParticipant(
                            conversationId: existingConvo.id,
                            userId: user.id,
                            joinedAt: Date(),
                            role: "member"
                        )
                        try await supabase
                            .from("conversation_participants")
                            .insert(participant)
                            .execute()
                    }

                    // Reload and return the existing conversation
                    await loadConversations()
                    return conversations.first { $0.conversation.id == existingConvo.id }
                }
            }

            // Create conversation with proper kind and canonical key
            let conversation = Conversation(
                id: UUID(),
                mode: mode,
                kind: kind,
                title: title,
                canonicalKey: canonicalKey,
                createdAt: Date(),
                updatedAt: Date()
            )

            try await supabase
                .from("conversations")
                .insert(conversation)
                .execute()

            // Add participants
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
            // Return the newly created conversation with details
            return conversations.first { $0.conversation.id == conversation.id }
        } catch {
            errorMessage = "Failed to create conversation: \(error.localizedDescription)"
            return nil
        }
    }

    /// Delete a conversation and its messages
    func deleteConversation(_ conversationId: UUID) async {
        // Optimistic UI update - remove from list immediately
        let previousConversations = conversations
        let previousSelection = selectedConversation

        conversations.removeAll { $0.conversation.id == conversationId }
        if selectedConversation?.conversation.id == conversationId {
            selectedConversation = nil
            messages = []
        }

        do {
            // Delete messages first (foreign key constraint)
            try await supabase
                .from("messages")
                .delete()
                .eq("conversation_id", value: conversationId.uuidString)
                .execute()

            // Delete participants
            try await supabase
                .from("conversation_participants")
                .delete()
                .eq("conversation_id", value: conversationId.uuidString)
                .execute()

            // Delete conversation
            try await supabase
                .from("conversations")
                .delete()
                .eq("id", value: conversationId.uuidString)
                .execute()

        } catch {
            // Rollback on failure
            conversations = previousConversations
            selectedConversation = previousSelection
            errorMessage = "Failed to delete: \(error.localizedDescription)"
        }
    }

    // MARK: - Messages

    func loadMessages(for conversationDetails: ConversationWithDetails) async {
        isLoading = true

        // Memory extraction: if switching to a different conversation, extract from previous
        let newConversationId = conversationDetails.conversation.id
        memoryLog("AppState", "Loading conversation \(newConversationId), previous was \(previousConversationId?.uuidString ?? "nil")")

        if let prevId = previousConversationId, prevId != newConversationId {
            memoryLog("AppState", "Conversation switch detected! Triggering extraction...")
            // Fire-and-forget extraction from previous conversation (runs in background)
            let prevMessages = self.previousMessages
            let prevParticipants = self.previousParticipants
            memoryLog("AppState", "Previous had \(prevMessages.count) messages, \(prevParticipants.count) participants")

            Task.detached {
                guard prevMessages.count >= 3 else {
                    memoryLog("Task", "Skipping: only \(prevMessages.count) messages (need 3+)")
                    return
                }
                guard let agentParticipant = prevParticipants.first(where: { $0.isAgent }) else {
                    memoryLog("Task", "Skipping: no agent found in participants")
                    return
                }
                let participantIds = prevParticipants.map { $0.id }
                memoryLog("Task", "Extracting from \(prevMessages.count) messages with agent \(agentParticipant.displayName)")
                let memories = await MediatorService.shared.extractMemories(
                    from: prevMessages,
                    agentId: agentParticipant.id,
                    participants: participantIds
                )
                memoryLog("Task", "Extracted \(memories.count) memories")
                var stored = 0
                for memory in memories {
                    if let confidenceStr = memory.metadata?["confidence"],
                       let confidence = Double(confidenceStr), confidence < 0.5 {
                        memoryLog("Task", "Skipping low-confidence: \(memory.title)")
                        continue
                    }
                    await MediatorService.shared.storeMemory(memory)
                    stored += 1
                }
                memoryLog("Task", "✅ Stored \(stored) memories in background")
            }
        }

        // Clear messages immediately to prevent showing stale data from previous conversation
        self.messages = []
        defer { isLoading = false }

        do {
            let msgs: [Message] = try await supabase
                .from("messages")
                .select()
                .eq("conversation_id", value: conversationDetails.conversation.id.uuidString)
                .order("created_at", ascending: true)
                .execute()
                .value

            // CRITICAL: Only update messages if this conversation is still selected
            // Prevents race condition where switching conversations causes message crossover
            guard selectedConversation?.conversation.id == conversationDetails.conversation.id else {
                print("📨 Skipping message update - conversation \(conversationDetails.conversation.id) no longer selected")
                return
            }

            self.messages = msgs
            print("📨 Loaded \(msgs.count) messages for conversation \(conversationDetails.conversation.id)")

            // Update conversation preview in sidebar with latest message
            if let lastMsg = msgs.last {
                updateConversationPreview(conversationId: conversationDetails.conversation.id, lastMessage: lastMsg)
            }

            // Track this conversation for memory extraction when we leave
            self.previousConversationId = conversationDetails.conversation.id
            self.previousMessages = msgs
            self.previousParticipants = conversationDetails.participants
        } catch {
            errorMessage = "Failed to load messages: \(error.localizedDescription)"
        }
    }

    /// Update a conversation's lastMessage in the conversations list (for sidebar preview)
    private func updateConversationPreview(conversationId: UUID, lastMessage: Message) {
        if let index = conversations.firstIndex(where: { $0.conversation.id == conversationId }) {
            var updated = conversations[index]
            updated = ConversationWithDetails(
                conversation: updated.conversation,
                participants: updated.participants,
                lastMessage: lastMessage,
                unreadCount: updated.unreadCount
            )
            conversations[index] = updated

            // Also update selectedConversation if it's the same one
            if selectedConversation?.conversation.id == conversationId {
                print("📋 [PREVIEW] Updating selectedConversation for: \(conversationId)")
                selectedConversation = updated
            } else {
                print("📋 [PREVIEW] NOT updating selectedConversation - IDs don't match")
                print("📋 [PREVIEW]   Selected: \(selectedConversation?.conversation.id.uuidString ?? "nil")")
                print("📋 [PREVIEW]   Updated:  \(conversationId)")
            }
        }
    }

    func sendMessage(content: String, attachments: [PendingAttachment] = [], to conversationDetails: ConversationWithDetails) async {
        let conversation = conversationDetails.conversation
        guard let user = currentUser else { return }

        // DEBUG: Log which conversation the message is being sent to
        print("📤 [SEND] Sending to conversation: \(conversation.id)")
        print("📤 [SEND] Selected conversation: \(selectedConversation?.conversation.id.uuidString ?? "nil")")
        print("📤 [SEND] Match: \(conversation.id == selectedConversation?.conversation.id)")

        // Create message ID upfront for optimistic UI
        let messageId = UUID()

        // Optimistic UI: Show user's message immediately (without attachments - they'll be added after upload)
        let optimisticMessage = Message(
            id: messageId,
            conversationId: conversation.id,
            senderId: user.id,
            contentRaw: content,
            contentProcessed: nil,
            isFromAgent: false,
            agentContext: nil,
            createdAt: Date(),
            processedAt: nil,
            rawVisibleTo: nil,
            attachments: nil
        )
        messages.append(optimisticMessage)

        // Update sidebar preview immediately
        updateConversationPreview(conversationId: conversation.id, lastMessage: optimisticMessage)

        do {
            var processedContent: String? = nil
            var agentContextData: AgentContextData? = nil

            // Upload attachments if any
            var uploadedAttachments: [MessageAttachment] = []
            print("📎 [UPLOAD] Starting upload of \(attachments.count) attachments")
            for pending in attachments {
                do {
                    print("📎 [UPLOAD] Uploading: \(pending.filename) (\(pending.originalData.count) bytes)")
                    let uploaded = try await ImageService.shared.upload(
                        attachment: pending,
                        conversationId: conversation.id
                    )
                    print("📎 [UPLOAD] Success! URL: \(uploaded.url)")
                    uploadedAttachments.append(uploaded)
                } catch {
                    print("📎 [UPLOAD] FAILED: \(error.localizedDescription)")
                    // Continue with other attachments
                }
            }
            print("📎 [UPLOAD] Finished with \(uploadedAttachments.count) uploaded")

            // Check if this is an agent-only chat (no human recipients)
            let hasHumanRecipients = conversationDetails.participants.contains { $0.isHuman }

            // Only process through AI mediator for human-to-human communication
            // Skip mediator for: direct mode, agent-only chats
            let shouldProcess = conversation.mode != .direct && hasHumanRecipients

            if shouldProcess {
                do {
                    // Get other participant name for context
                    let recipientName = conversation.title ?? "Recipient"

                    // Load agent context
                    let agentContext = try await MediatorService.shared.loadAgentContext(for: conversation.id)

                    // Process the message
                    let processed = try await MediatorService.shared.processMessage(
                        rawContent: content,
                        mode: conversation.mode,
                        senderName: user.displayName,
                        recipientName: recipientName,
                        conversationHistory: messages,
                        agentContext: agentContext
                    )

                    processedContent = processed.content

                    // Store processing metadata as JSON
                    // Build agent context if we have any metadata
                    if processed.summary != nil || processed.sentiment != nil || processed.actionItems != nil {
                        agentContextData = AgentContextData(
                            summary: processed.summary,
                            sentiment: processed.sentiment,
                            actionItems: processed.actionItems
                        )
                    }
                } catch {
                    // Log error but still send raw message
                    print("AI processing failed: \(error.localizedDescription)")
                    // For anonymous mode, we should probably not send without processing
                    if conversation.mode == .anonymous {
                        errorMessage = "AI processing failed. Cannot send anonymous message."
                        return
                    }
                }
            }

            let message = Message(
                id: messageId,  // Use same ID as optimistic message
                conversationId: conversation.id,
                senderId: user.id,
                contentRaw: content,
                contentProcessed: processedContent,
                isFromAgent: false,
                agentContext: agentContextData,
                createdAt: Date(),
                processedAt: processedContent != nil ? Date() : nil,
                rawVisibleTo: nil,
                attachments: uploadedAttachments.isEmpty ? nil : uploadedAttachments
            )

            print("📎 [DB] Inserting message with \(message.attachments?.count ?? 0) attachments")
            if let atts = message.attachments {
                for att in atts {
                    print("📎 [DB] Attachment: \(att.url)")
                }
            }

            try await supabase
                .from("messages")
                .insert(message)
                .execute()

            print("📎 [DB] Message inserted successfully")

            // Update optimistic message with processed content and attachments
            // Only if still viewing the same conversation (prevents race condition)
            if processedContent != nil || !uploadedAttachments.isEmpty {
                if selectedConversation?.conversation.id == conversation.id,
                   let index = messages.firstIndex(where: { $0.id == messageId }) {
                    messages[index] = message
                }
            }

            // Check which agents should respond based on @mentions
            let agentParticipants = conversationDetails.participants.filter { $0.isAgent }
            let allAgents = await loadAgents()

            // DEBUG: Log participant info to track down unwanted STEF responses
            print("🔍 [AGENT-CHECK] Participants: \(conversationDetails.participants.map { "\($0.displayName) (agent=\($0.isAgent))" })")
            print("🔍 [AGENT-CHECK] Agent participants: \(agentParticipants.map { $0.displayName })")
            print("🔍 [AGENT-CHECK] All agents in system: \(allAgents.map { $0.displayName })")

            // Determine which agents to trigger:
            // 1. In auto-respond conversations (Green Room): all agents respond
            // 2. In true 1:1 with single agent: that agent always responds
            // 3. Otherwise: only respond if @mentioned (prevents double-triggers)
            let isAutoRespondConversation = KnownConversation.autoRespondConversations.contains(conversation.id)
            let isAgentOnlyChat = conversationDetails.participants.allSatisfy { $0.isAgent || $0.id == user.id }
            let agentCount = agentParticipants.count

            print("🔍 [AGENT-CHECK] isAutoRespond=\(isAutoRespondConversation), isAgentOnlyChat=\(isAgentOnlyChat), agentCount=\(agentCount)")

            var agentsToRespond: [User] = []

            if isAutoRespondConversation {
                // Auto-respond conversation (like Green Room) - all agent participants respond
                print("🔍 [AGENT-CHECK] Path: auto-respond conversation, all agents respond")
                agentsToRespond = agentParticipants
            } else if isAgentOnlyChat && agentCount == 1 {
                // True 1:1 with single agent - always respond
                print("🔍 [AGENT-CHECK] Path: 1:1 with single agent, auto-responding")
                agentsToRespond = agentParticipants
            } else {
                // Multi-agent chat or mixed - only respond if @mentioned
                // This prevents double-triggers when one agent @mentions another
                print("🔍 [AGENT-CHECK] Path: checking @mentions in '\(content)'")
                for agent in agentParticipants {
                    let mentioned = MediatorService.shared.isAgentMentioned(agent, in: content)
                    print("🔍 [AGENT-CHECK] Participant \(agent.displayName) mentioned=\(mentioned)")
                    if mentioned {
                        agentsToRespond.append(agent)
                    }
                }
                // Also check for agents not in conversation but @mentioned
                for agent in allAgents where !agentParticipants.contains(where: { $0.id == agent.id }) {
                    let mentioned = MediatorService.shared.isAgentMentioned(agent, in: content)
                    print("🔍 [AGENT-CHECK] Non-participant \(agent.displayName) mentioned=\(mentioned)")
                    if mentioned {
                        agentsToRespond.append(agent)
                    }
                }
            }

            // Filter out external agents (like Terminal STEF) that don't respond via in-app API
            agentsToRespond = agentsToRespond.filter { !AppState.externalAgentIds.contains($0.id) }

            print("🔍 [AGENT-CHECK] Final agentsToRespond: \(agentsToRespond.map { $0.displayName })")

            // Mark this message as being handled to prevent realtime subscription from double-triggering
            // The realtime handler checks this set before generating responses
            if !agentsToRespond.isEmpty {
                recentlyRespondedMessages.insert(messageId)
                // Clean up after debounce period
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(responseDebounceSeconds * 1_000_000_000))
                    recentlyRespondedMessages.remove(messageId)
                }
            }

            // Generate responses from mentioned agents
            for agent in agentsToRespond {
                await generateAndSendAgentResponse(
                    agent: agent,
                    userMessage: content,
                    senderName: user.displayName,
                    conversation: conversation,
                    conversationDetails: conversationDetails,
                    allAgents: allAgents,
                    attachments: uploadedAttachments.isEmpty ? nil : uploadedAttachments
                )
            }
        } catch {
            errorMessage = "Failed to send message: \(error.localizedDescription)"
        }
    }

    /// Generate and send a response from an AI agent
    /// Also checks if the agent @mentions other agents, triggering their responses
    private func generateAndSendAgentResponse(
        agent: User,
        userMessage: String,
        senderName: String,
        conversation: Conversation,
        conversationDetails: ConversationWithDetails,
        allAgents: [User],
        attachments: [MessageAttachment]? = nil,
        depth: Int = 0
    ) async {
        // Prevent infinite loops - max 2 levels of agent-to-agent
        guard depth < 2 else {
            print("Max agent response depth reached")
            return
        }

        do {
            // Generate response from the agent (with potential GitHub actions)
            let response = try await MediatorService.shared.generateAgentResponseWithActions(
                to: userMessage,
                from: agent,
                conversationHistory: messages,
                senderName: senderName,
                participants: conversationDetails.participants,
                conversationId: conversation.id,
                attachments: attachments
            )

            let messageId = UUID()

            // Store any proposed actions for the UI to display
            if !response.actions.isEmpty {
                await MainActor.run {
                    pendingActions[messageId] = response.actions
                }
                print("📋 [AppState] Stored \(response.actions.count) pending action(s) for message \(messageId)")
            }

            // Execute cross-conversation messages (tool use results)
            // Track agents triggered via cross-conversation to avoid double-triggering in cascade
            var agentsTriggeredViaCrossConversation: Set<UUID> = []

            if !response.crossConversationMessages.isEmpty {
                print("🧠 [AppState] Sending \(response.crossConversationMessages.count) cross-conversation message(s)")
                for crossMsg in response.crossConversationMessages {
                    // Skip if targeting the current conversation (redundant - use response.text instead)
                    // Don't track these agents - they'll be triggered by the cascade from response.text
                    if crossMsg.targetConversationId == conversation.id {
                        print("🧠 [AppState] Skipping cross-conversation to SAME conversation (redundant)")
                        continue
                    }

                    await sendCrossConversationMessage(
                        from: agent,
                        to: crossMsg.targetConversationId,
                        content: crossMsg.content
                    )

                    // Track agents triggered in cross-conversation messages
                    for otherAgent in allAgents where otherAgent.id != agent.id {
                        if MediatorService.shared.isAgentMentioned(otherAgent, in: crossMsg.content) {
                            agentsTriggeredViaCrossConversation.insert(otherAgent.id)
                        }
                    }
                }
            }

            // Create the agent's message
            let agentMessage = Message(
                id: messageId,
                conversationId: conversation.id,
                senderId: agent.id,
                contentRaw: response.text,
                contentProcessed: nil,
                isFromAgent: true,
                agentContext: nil,
                createdAt: Date(),
                processedAt: nil,
                rawVisibleTo: nil,
                attachments: nil
            )

            // Insert the agent's response
            try await supabase
                .from("messages")
                .insert(agentMessage)
                .execute()

            // Reload messages to show the agent's response
            await loadMessages(for: conversationDetails)

            // Check if this agent @mentioned other agents - trigger their responses
            // Exclude external agents (like Terminal STEF) that respond via Claude Code, not in-app API
            // Also exclude agents already triggered via cross-conversation messages (avoid duplicates)
            let otherAgents = allAgents.filter {
                $0.id != agent.id &&
                !AppState.externalAgentIds.contains($0.id) &&
                !agentsTriggeredViaCrossConversation.contains($0.id)
            }
            for otherAgent in otherAgents {
                if MediatorService.shared.isAgentMentioned(otherAgent, in: response.text) {
                    // Small delay to make conversation feel more natural
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second

                    await generateAndSendAgentResponse(
                        agent: otherAgent,
                        userMessage: response.text,
                        senderName: agent.displayName,
                        conversation: conversation,
                        conversationDetails: conversationDetails,
                        allAgents: allAgents,
                        depth: depth + 1
                    )
                }
            }

        } catch {
            print("Agent response generation failed: \(error.localizedDescription)")
            // Don't show error to user - agent response is optional
        }
    }

    // MARK: - GitHub Actions

    /// Execute a GitHub action and remove it from pending
    func executeGitHubAction(_ action: GitHubAction, forMessageId messageId: UUID) async {
        do {
            switch action {
            case .createIssue(let title, let body, let labels):
                let issueNumber = try await GitHubService.shared.createIssue(
                    title: title,
                    body: body,
                    labels: labels
                )
                print("✅ Created issue #\(issueNumber): \(title)")

                // Optionally notify in chat (send a follow-up message)
                // For now just log success

            case .addComment(let issueNumber, let body):
                try await GitHubService.shared.addComment(issueNumber: issueNumber, body: body)
                print("✅ Added comment to issue #\(issueNumber)")

            case .readIssue(let issueNumber):
                let details = try await GitHubService.shared.fetchIssueDetails(issueNumber: issueNumber)
                let comments = try await GitHubService.shared.fetchIssueComments(issueNumber: issueNumber)
                print("📖 Issue #\(issueNumber): \(details.title)")
                print("   Body: \(details.body ?? "(no body)")")
                for comment in comments {
                    print("   💬 \(comment.user.login): \(comment.body.prefix(100))...")
                }
            }

            // Remove the executed action from pending
            await MainActor.run {
                if var actions = pendingActions[messageId] {
                    actions.removeAll { $0 == action }
                    if actions.isEmpty {
                        pendingActions.removeValue(forKey: messageId)
                    } else {
                        pendingActions[messageId] = actions
                    }
                }
            }

        } catch {
            print("❌ Failed to execute GitHub action: \(error.localizedDescription)")
            await MainActor.run {
                errorMessage = "GitHub action failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Cross-Conversation Messaging

    /// Send a message from an agent to a different conversation
    /// Also triggers @mentioned agents to respond in the target conversation
    private func sendCrossConversationMessage(
        from agent: User,
        to conversationId: UUID,
        content: String
    ) async {
        do {
            let message = Message(
                id: UUID(),
                conversationId: conversationId,
                senderId: agent.id,
                contentRaw: content,
                contentProcessed: nil,
                isFromAgent: true,
                agentContext: AgentContextData(
                    sourceAgent: "app-stef",
                    trigger: "tool_use:send_to_corpus_callosum"
                ),
                createdAt: Date(),
                processedAt: nil,
                rawVisibleTo: nil,
                attachments: nil
            )

            try await supabase
                .from("messages")
                .insert(message)
                .execute()

            print("🧠 [CrossConversation] Sent message to \(conversationId): \(content.prefix(50))...")

            // Trigger @mentioned agents in the target conversation
            await triggerMentionedAgentsInConversation(
                conversationId: conversationId,
                messageContent: content,
                senderAgent: agent
            )
        } catch {
            print("❌ [CrossConversation] Failed to send: \(error.localizedDescription)")
        }
    }

    /// Trigger responses from @mentioned agents in a conversation
    private func triggerMentionedAgentsInConversation(
        conversationId: UUID,
        messageContent: String,
        senderAgent: User
    ) async {
        // Load target conversation details
        guard let conversation = await loadConversation(byId: conversationId) else {
            print("❌ [CrossConversation] Could not load target conversation")
            return
        }

        let conversationDetails = await loadConversationDetails(conversation, currentUserId: senderAgent.id)
        let allAgents = await loadAgents()

        // Find @mentioned agents (excluding sender and external agents)
        let mentionedAgents = allAgents.filter { otherAgent in
            otherAgent.id != senderAgent.id &&
            !AppState.externalAgentIds.contains(otherAgent.id) &&
            MediatorService.shared.isAgentMentioned(otherAgent, in: messageContent)
        }

        guard !mentionedAgents.isEmpty else {
            print("🧠 [CrossConversation] No agents @mentioned in message")
            return
        }

        print("🧠 [CrossConversation] Triggering responses from: \(mentionedAgents.map { $0.displayName })")

        // Generate responses from each @mentioned agent
        for mentionedAgent in mentionedAgents {
            // Small delay between agent responses
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second

            await generateAndSendAgentResponse(
                agent: mentionedAgent,
                userMessage: messageContent,
                senderName: senderAgent.displayName,
                conversation: conversation,
                conversationDetails: conversationDetails,
                allAgents: allAgents,
                depth: 1  // Start at depth 1 since this is already a cascade
            )
        }
    }

    /// Load a single conversation by ID
    private func loadConversation(byId id: UUID) async -> Conversation? {
        do {
            let conversations: [Conversation] = try await supabase
                .from("conversations")
                .select()
                .eq("id", value: id.uuidString)
                .execute()
                .value
            return conversations.first
        } catch {
            print("❌ Failed to load conversation \(id): \(error.localizedDescription)")
            return nil
        }
    }

    /// Dismiss a pending action without executing it
    func dismissGitHubAction(_ action: GitHubAction, forMessageId messageId: UUID) {
        if var actions = pendingActions[messageId] {
            actions.removeAll { $0 == action }
            if actions.isEmpty {
                pendingActions.removeValue(forKey: messageId)
            } else {
                pendingActions[messageId] = actions
            }
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

    /// Load all users, optionally filtering by type
    /// - Parameter includeAgents: If false, only returns human users
    /// - Returns: Array of users sorted by type (agents first) then name
    func loadAllUsers(includeAgents: Bool = true) async -> [User] {
        do {
            var users: [User] = try await supabase
                .from("users")
                .select()
                .order("display_name", ascending: true)
                .execute()
                .value

            if !includeAgents {
                users = users.filter { $0.isHuman }
            }

            // Sort: agents first, then by display name
            users.sort { user1, user2 in
                if user1.isAgent != user2.isAgent {
                    return user1.isAgent  // Agents come first
                }
                return user1.displayName.localizedCaseInsensitiveCompare(user2.displayName) == .orderedAscending
            }

            return users
        } catch {
            errorMessage = "Failed to load contacts: \(error.localizedDescription)"
            return []
        }
    }

    /// Load only AI agent users
    func loadAgents() async -> [User] {
        do {
            let users: [User] = try await supabase
                .from("users")
                .select()
                .eq("user_type", value: "agent")
                .order("display_name", ascending: true)
                .execute()
                .value
            return users
        } catch {
            errorMessage = "Failed to load agents: \(error.localizedDescription)"
            return []
        }
    }

    /// Load only human users
    func loadHumanUsers() async -> [User] {
        do {
            let users: [User] = try await supabase
                .from("users")
                .select()
                .eq("user_type", value: "human")
                .order("display_name", ascending: true)
                .execute()
                .value
            return users
        } catch {
            errorMessage = "Failed to load contacts: \(error.localizedDescription)"
            return []
        }
    }

    func createUser(displayName: String, githubHandle: String?, phoneNumber: String?, email: String?, userType: UserType = .human) async -> User? {
        do {
            let newUser = User(
                id: UUID(),
                githubHandle: githubHandle,
                displayName: displayName,
                email: email,
                phoneNumber: phoneNumber,
                avatarUrl: nil,
                userType: userType,
                agentMetadata: nil,
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
        // Prevent deletion of system agents
        if id == AppState.stefAgentId {
            errorMessage = "Cannot delete system agents"
            return
        }

        // Check if user is a system agent before deleting
        if let user = await loadUser(byId: id), user.isSystemAgent {
            errorMessage = "Cannot delete system agents"
            return
        }

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
        } catch is CancellationError {
            // Task was cancelled (e.g., user switched tabs) - ignore
        } catch let urlError as URLError where urlError.code == .cancelled {
            // URLSession task was cancelled - ignore
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
        } catch is CancellationError {
            // Task was cancelled - ignore
        } catch let urlError as URLError where urlError.code == .cancelled {
            // URLSession task was cancelled - ignore
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
                .update(["status": status.rawValue, "status_changed_at": Formatters.iso8601Now()])
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
        } catch is CancellationError {
            // Task was cancelled - ignore
        } catch let urlError as URLError where urlError.code == .cancelled {
            // URLSession task was cancelled - ignore
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

    // MARK: - Agent Memory System

    /// Extract and store memories when leaving a conversation (per STEF's suggestion)
    private func extractMemoriesFromPreviousConversation() async {
        // Need at least 3 messages and an agent participant for extraction
        guard previousMessages.count >= 3,
              let agentParticipant = previousParticipants.first(where: { $0.isAgent }) else {
            return
        }

        let participantIds = previousParticipants.map { $0.id }

        print("🧠 [Memory] Extracting memories from conversation with \(previousMessages.count) messages")

        let memories = await MediatorService.shared.extractMemories(
            from: previousMessages,
            agentId: agentParticipant.id,
            participants: participantIds
        )

        // Store each extracted memory
        for memory in memories {
            // Filter out low-confidence memories (< 0.5)
            if let confidenceStr = memory.metadata?["confidence"],
               let confidence = Double(confidenceStr),
               confidence < 0.5 {
                print("🧠 [Memory] Skipping low-confidence memory: \(memory.title)")
                continue
            }

            await MediatorService.shared.storeMemory(memory)
        }

        print("🧠 [Memory] Stored \(memories.count) memories from previous conversation")
    }

    // MARK: - Agent Management

    /// Load agent config for a specific agent
    func loadAgentConfig(for agentId: UUID) async -> AgentConfig? {
        do {
            let configs: [AgentConfig] = try await supabase
                .from("agent_configs")
                .select()
                .eq("user_id", value: agentId.uuidString)
                .execute()
                .value
            return configs.first
        } catch {
            errorMessage = "Failed to load agent config: \(error.localizedDescription)"
            return nil
        }
    }

    /// Load all agent configs (for admin view)
    func loadAllAgentConfigs() async -> [AgentConfig] {
        do {
            let configs: [AgentConfig] = try await supabase
                .from("agent_configs")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value
            return configs
        } catch {
            errorMessage = "Failed to load agent configs: \(error.localizedDescription)"
            return []
        }
    }

    /// Create a new AI agent with config
    func createAgent(
        displayName: String,
        systemPrompt: String,
        description: String?,
        backstory: String?,
        voiceStyle: String?,
        model: AgentModel,
        temperature: Double,
        isPublic: Bool,
        capabilities: [String]
    ) async -> User? {
        guard let creator = currentUser else { return nil }

        let agentId = UUID()

        do {
            // Create the user record
            let agentMetadata = AgentMetadata(
                provider: "anthropic",
                model: model.rawValue,
                capabilities: capabilities.isEmpty ? ["conversation"] : capabilities,
                isSystem: false
            )

            let newAgent = User(
                id: agentId,
                githubHandle: nil,
                displayName: displayName,
                email: nil,
                phoneNumber: nil,
                avatarUrl: nil,
                userType: .agent,
                agentMetadata: agentMetadata,
                createdAt: Date(),
                updatedAt: Date()
            )

            try await supabase
                .from("users")
                .insert(newAgent)
                .execute()

            // Create the config record
            let config = AgentConfig(
                userId: agentId,
                systemPrompt: systemPrompt,
                backstory: backstory,
                voiceStyle: voiceStyle,
                canInitiate: false,
                model: model.rawValue,
                temperature: temperature,
                isPublic: isPublic,
                createdBy: creator.id,
                description: description
            )

            try await supabase
                .from("agent_configs")
                .insert(config)
                .execute()

            // Clear the config cache in MediatorService
            MediatorService.shared.clearConfigCache()

            return newAgent
        } catch {
            errorMessage = "Failed to create agent: \(error.localizedDescription)"
            return nil
        }
    }

    /// Update an existing agent and its config
    func updateAgent(
        agentId: UUID,
        displayName: String,
        systemPrompt: String,
        description: String?,
        backstory: String?,
        voiceStyle: String?,
        model: AgentModel,
        temperature: Double,
        isPublic: Bool,
        capabilities: [String]
    ) async -> Bool {
        do {
            // Update user record
            let agentMetadata = AgentMetadata(
                provider: "anthropic",
                model: model.rawValue,
                capabilities: capabilities.isEmpty ? ["conversation"] : capabilities,
                isSystem: false
            )

            let userUpdate = AgentUserUpdate(
                displayName: displayName,
                agentMetadata: agentMetadata,
                updatedAt: Date()
            )

            try await supabase
                .from("users")
                .update(userUpdate)
                .eq("id", value: agentId.uuidString)
                .execute()

            // Update config record
            let configUpdate = AgentConfigUpdate(
                systemPrompt: systemPrompt,
                description: description,
                backstory: backstory,
                voiceStyle: voiceStyle,
                model: model.rawValue,
                temperature: temperature,
                isPublic: isPublic,
                updatedAt: Date()
            )

            try await supabase
                .from("agent_configs")
                .update(configUpdate)
                .eq("user_id", value: agentId.uuidString)
                .execute()

            // Clear the config cache
            MediatorService.shared.clearConfigCache()

            return true
        } catch {
            errorMessage = "Failed to update agent: \(error.localizedDescription)"
            return false
        }
    }

    /// Delete an agent (non-system only)
    func deleteAgent(_ agentId: UUID) async -> Bool {
        // Prevent deletion of system agents
        if agentId == AppState.stefAgentId {
            errorMessage = "Cannot delete system agents"
            return false
        }

        if let user = await loadUser(byId: agentId), user.isSystemAgent {
            errorMessage = "Cannot delete system agents"
            return false
        }

        do {
            // Delete config first (foreign key)
            try await supabase
                .from("agent_configs")
                .delete()
                .eq("user_id", value: agentId.uuidString)
                .execute()

            // Delete user
            try await supabase
                .from("users")
                .delete()
                .eq("id", value: agentId.uuidString)
                .execute()

            MediatorService.shared.clearConfigCache()
            return true
        } catch {
            errorMessage = "Failed to delete agent: \(error.localizedDescription)"
            return false
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

// Helper struct for agent user updates
struct AgentUserUpdate: Encodable {
    let displayName: String
    let agentMetadata: AgentMetadata
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case agentMetadata = "agent_metadata"
        case updatedAt = "updated_at"
    }
}

// Helper struct for agent config updates
struct AgentConfigUpdate: Encodable {
    let systemPrompt: String
    let description: String?
    let backstory: String?
    let voiceStyle: String?
    let model: String
    let temperature: Double
    let isPublic: Bool
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case systemPrompt = "system_prompt"
        case description
        case backstory
        case voiceStyle = "voice_style"
        case model
        case temperature
        case isPublic = "is_public"
        case updatedAt = "updated_at"
    }
}
