import SwiftUI
import AppKit

// NSTextField wrapper for reliable input
struct MessageTextField: NSViewRepresentable {
    var placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .exterior
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: MessageTextField

        init(_ parent: MessageTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}

struct ConversationView: View {
    @EnvironmentObject var appState: AppState
    let conversationDetails: ConversationWithDetails
    @State private var newMessage = ""
    @State private var showDeleteConfirmation = false

    private var conversation: Conversation { conversationDetails.conversation }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            conversationHeader

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(appState.messages) { message in
                            MessageBubble(
                                message: message,
                                isFromCurrentUser: message.senderId == appState.currentUser?.id,
                                conversationMode: conversation.mode
                            )
                            .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: appState.messages.count) { _, _ in
                    if let lastMessage = appState.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input
            messageInput
        }
        .task {
            await appState.loadMessages(for: conversationDetails)
        }
        .onChange(of: conversationDetails) { _, newDetails in
            Task {
                await appState.loadMessages(for: newDetails)
            }
        }
    }

    var conversationHeader: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(conversationDetails.displayTitle)
                    .font(.headline)
                HStack(spacing: 4) {
                    modeIcon
                    Text(modeLabel)
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }

            Spacer()

            // Refresh button
            Button(action: {
                Task { await appState.loadMessages(for: conversationDetails) }
            }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")

            // Delete button
            Button {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .help("Delete Conversation")
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .alert("Delete Conversation?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteCurrentConversation()
            }
        } message: {
            Text("This will permanently delete this conversation and all its messages.")
        }
    }

    var modeIcon: some View {
        Group {
            switch conversation.mode {
            case .anonymous:
                Image(systemName: "eye.slash")
                    .foregroundColor(.purple)
            case .assisted:
                Image(systemName: "sparkles")
                    .foregroundColor(.blue)
            case .direct:
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundColor(.green)
            }
        }
    }

    var modeLabel: String {
        switch conversation.mode {
        case .anonymous: return "Anonymous"
        case .assisted: return "AI Assisted"
        case .direct: return "Direct"
        }
    }

    var messageInput: some View {
        HStack(spacing: 12) {
            MessageTextField(placeholder: "Type a message...", text: $newMessage) {
                sendMessage()
            }
            .frame(height: 28)
            .padding(4)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            Button(action: sendMessage) {
                Image(systemName: "paperplane.fill")
                    .font(.title2)
            }
            .buttonStyle(.borderedProminent)
            .disabled(newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding()
    }

    func sendMessage() {
        let content = newMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        Task {
            await appState.sendMessage(content: content, to: conversationDetails)
            newMessage = ""
        }
    }

    func deleteCurrentConversation() {
        let idToDelete = conversationDetails.conversation.id
        Task {
            await appState.deleteConversation(idToDelete)
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: Message
    let isFromCurrentUser: Bool
    let conversationMode: ConversationMode

    /// What content to display based on mode and sender
    var displayContent: String {
        switch conversationMode {
        case .direct:
            return message.contentRaw
        case .assisted:
            // Show raw content (processed shown separately below)
            return message.contentRaw
        case .anonymous:
            // Sender sees their raw message, recipient sees processed
            if isFromCurrentUser {
                return message.contentRaw
            } else {
                return message.contentProcessed ?? message.contentRaw
            }
        }
    }

    /// Whether to show the AI-processed badge/content
    var showProcessedContent: Bool {
        guard let _ = message.contentProcessed else { return false }
        return conversationMode == .assisted
    }

    /// Whether this message was AI-processed
    var wasProcessed: Bool {
        message.contentProcessed != nil
    }

    var body: some View {
        HStack {
            if isFromCurrentUser { Spacer() }

            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                // Sender indicator
                if message.isFromAgent {
                    Label("AI Mediator", systemImage: "cpu")
                        .font(.caption2)
                        .foregroundColor(.purple)
                }

                // Anonymous mode indicator for recipient
                if conversationMode == .anonymous && !isFromCurrentUser && wasProcessed {
                    HStack(spacing: 4) {
                        Image(systemName: "eye.slash")
                        Text("AI-Mediated")
                    }
                    .font(.caption2)
                    .foregroundColor(.purple)
                }

                // Message content
                Text(displayContent)
                    .padding(12)
                    .background(messageBubbleColor)
                    .foregroundColor(messageForegroundColor)
                    .cornerRadius(16)

                // AI processed summary (for assisted mode)
                if showProcessedContent, let processed = message.contentProcessed {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                            Text("AI Summary")
                                .fontWeight(.medium)
                        }
                        .font(.caption)
                        .foregroundColor(.purple)

                        Text(processed)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal, 4)
                }

                // Processing indicator for sender in non-direct modes
                if isFromCurrentUser && conversationMode != .direct {
                    HStack(spacing: 4) {
                        if wasProcessed {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("AI Processed")
                        } else {
                            Image(systemName: "clock")
                                .foregroundColor(.orange)
                            Text("Processing...")
                        }
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }

                // Timestamp
                Text(message.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if !isFromCurrentUser { Spacer() }
        }
    }

    var messageBubbleColor: Color {
        if conversationMode == .anonymous && !isFromCurrentUser && wasProcessed {
            // AI-mediated messages have a purple tint
            return Color.purple.opacity(0.2)
        }
        return isFromCurrentUser ? Color.blue : Color(nsColor: .controlBackgroundColor)
    }

    var messageForegroundColor: Color {
        if conversationMode == .anonymous && !isFromCurrentUser && wasProcessed {
            return .primary
        }
        return isFromCurrentUser ? .white : .primary
    }
}
