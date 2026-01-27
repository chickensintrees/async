import SwiftUI
import AppKit

struct NewConversationView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var selectedParticipants: Set<UUID> = []
    @State private var allContacts: [User] = []
    @State private var title = ""
    @State private var selectedMode: ConversationMode = .assisted
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var modeWarning: String?

    // Filter out current user from contacts
    var availableContacts: [User] {
        let currentUserId = appState.currentUser?.id
        return allContacts.filter { $0.id != currentUserId }
    }

    var filteredContacts: [User] {
        if searchText.isEmpty { return availableContacts }
        return availableContacts.filter { contact in
            contact.displayName.localizedCaseInsensitiveContains(searchText) ||
            (contact.githubHandle?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var agents: [User] { filteredContacts.filter { $0.isAgent } }
    var humans: [User] { filteredContacts.filter { $0.isHuman } }

    var selectedUsers: [User] {
        allContacts.filter { selectedParticipants.contains($0.id) }
    }

    var hasSelectedAgent: Bool {
        selectedUsers.contains { $0.isAgent }
    }

    var hasSelectedHuman: Bool {
        selectedUsers.contains { $0.isHuman }
    }

    /// True when only AI agents are selected (no humans)
    /// In this case, mode picker should be hidden - it's inherently "assisted"
    var isAgentOnlyChat: Bool {
        !selectedParticipants.isEmpty && hasSelectedAgent && !hasSelectedHuman
    }

    /// The effective mode - forced to .assisted for agent-only chats
    var effectiveMode: ConversationMode {
        isAgentOnlyChat ? .assisted : selectedMode
    }

    // Computed participants based on mode rules
    var participantsForConversation: [UUID] {
        var participants = Array(selectedParticipants)

        switch effectiveMode {
        case .direct:
            // Direct mode: remove any agents
            participants = participants.filter { id in
                allContacts.first { $0.id == id }?.isHuman == true
            }
        case .anonymous:
            // Anonymous mode: ensure STEF is included
            if !participants.contains(AppState.stefAgentId) {
                participants.append(AppState.stefAgentId)
            }
        case .assisted:
            // No changes needed
            break
        }

        return participants
    }

    var canCreate: Bool {
        let finalParticipants = participantsForConversation
        // Need at least one participant other than potential auto-added agents
        let hasHumanRecipient = finalParticipants.contains { id in
            allContacts.first { $0.id == id }?.isHuman == true
        }
        // Agent-only chats don't require human recipients
        return !selectedParticipants.isEmpty && (hasHumanRecipient || isAgentOnlyChat || effectiveMode != .anonymous)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Conversation")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            // Search bar
            SearchBar(text: $searchText, placeholder: "Search contacts...")
                .padding(.horizontal)
                .padding(.vertical, 8)

            // Selected participants chips
            if !selectedParticipants.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(selectedUsers) { user in
                            ParticipantChip(contact: user) {
                                selectedParticipants.remove(user.id)
                                updateModeWarning()
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 36)

                Divider()
            }

            if isLoading {
                ProgressView("Loading contacts...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Contact picker
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Agents section
                        if !agents.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkles")
                                        .foregroundColor(.purple)
                                    Text("AI Agents")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.purple)
                                }
                                .padding(.bottom, 4)

                                ForEach(agents) { contact in
                                    ParticipantSelectRow(
                                        contact: contact,
                                        isSelected: selectedParticipants.contains(contact.id),
                                        onToggle: { toggleParticipant(contact.id) }
                                    )
                                }
                            }
                        }

                        // People section
                        if !humans.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: "person.2.fill")
                                        .foregroundColor(.blue)
                                    Text("People")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.blue)
                                }
                                .padding(.bottom, 4)

                                ForEach(humans) { contact in
                                    ParticipantSelectRow(
                                        contact: contact,
                                        isSelected: selectedParticipants.contains(contact.id),
                                        onToggle: { toggleParticipant(contact.id) }
                                    )
                                }
                            }
                        }

                        // No results
                        if !searchText.isEmpty && agents.isEmpty && humans.isEmpty {
                            HStack {
                                Spacer()
                                VStack(spacing: 8) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                    Text("No contacts match \"\(searchText)\"")
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 20)
                        }

                        Divider()
                            .padding(.vertical, 8)

                        // Title Section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Title (Optional)")
                                .font(.headline)

                            TextField("e.g., Project Discussion", text: $title)
                                .textFieldStyle(.roundedBorder)
                        }

                        // Mode Section - Hidden for agent-only chats
                        if !isAgentOnlyChat {
                            Divider()
                                .padding(.vertical, 8)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Message Processing")
                                    .font(.headline)

                                Picker("Mode", selection: $selectedMode) {
                                    ForEach(ConversationMode.allCases, id: \.self) { mode in
                                        VStack(alignment: .leading) {
                                            Text(mode.displayName)
                                            Text(mode.description)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        .tag(mode)
                                    }
                                }
                                .pickerStyle(.radioGroup)
                                .labelsHidden()
                                .onChange(of: selectedMode) { _, _ in
                                    updateModeWarning()
                                }

                                // Mode warning
                                if let warning = modeWarning {
                                    HStack(spacing: 6) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                        Text(warning)
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                    .padding(.top, 4)
                                }
                            }
                        } else {
                            // Agent-only chat info
                            Divider()
                                .padding(.vertical, 8)

                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .foregroundColor(.purple)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("AI Agent Chat")
                                        .font(.headline)
                                    Text("Messages will be sent directly to the AI agent")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .padding()
                }
            }

            Divider()

            // Actions
            HStack {
                // Participant count
                if !selectedParticipants.isEmpty {
                    Text("\(selectedParticipants.count) participant\(selectedParticipants.count == 1 ? "" : "s") selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Button("Create Conversation") {
                    createConversation()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canCreate)
                .keyboardShortcut(.return)
            }
            .padding()
        }
        .frame(width: 500, height: 650)
        .task {
            await loadContacts()
        }
    }

    func toggleParticipant(_ id: UUID) {
        if selectedParticipants.contains(id) {
            selectedParticipants.remove(id)
        } else {
            selectedParticipants.insert(id)
        }
        updateModeWarning()
    }

    func updateModeWarning() {
        modeWarning = nil

        switch selectedMode {
        case .direct:
            // No warnings needed - agents can still respond via @mentions
            break
        case .anonymous:
            if !hasSelectedHuman {
                modeWarning = "Mediated mode requires at least one human recipient"
            } else if !hasSelectedAgent {
                modeWarning = "STEF will be added to process messages"
            }
        case .assisted:
            break
        }
    }

    func loadContacts() async {
        isLoading = true
        allContacts = await appState.loadAllUsers()
        isLoading = false
    }

    func createConversation() {
        let participants = participantsForConversation
        guard !participants.isEmpty else { return }

        Task {
            // Check if conversation with EXACT same participants already exists (same mode, no title)
            if title.isEmpty && participants.count == 1 {
                let recipientId = participants.first!
                if let existing = appState.conversations.first(where: { convo in
                    // Must be a true 1:1 conversation (kind check)
                    convo.conversation.is1to1 &&
                    // Exactly one other participant
                    convo.participants.count == 1 &&
                    // That participant is our recipient
                    convo.participants.first?.id == recipientId &&
                    // Same communication mode
                    convo.conversation.mode == effectiveMode &&
                    // No custom title (untitled DMs are reusable)
                    (convo.conversation.title == nil || convo.conversation.title?.isEmpty == true)
                }) {
                    // Open existing conversation instead of creating duplicate
                    appState.selectedConversation = existing
                    dismiss()
                    return
                }
            }

            // Create new conversation with effective mode
            if let conversation = await appState.createConversation(
                with: participants,
                mode: effectiveMode,
                title: title.isEmpty ? nil : title
            ) {
                appState.selectedConversation = conversation
                dismiss()
            }
        }
    }
}
