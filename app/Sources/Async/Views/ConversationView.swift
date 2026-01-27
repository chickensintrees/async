import SwiftUI
import AppKit

// MARK: - Growing Text Input (multi-line, handles large paste)

struct GrowingTextInput: NSViewRepresentable {
    var placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()

        // Configure text view
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.drawsBackground = false

        // Configure scroll view
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if textView.string != text {
            textView.string = text
        }

        // Update placeholder visibility
        context.coordinator.updatePlaceholder()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GrowingTextInput
        weak var textView: NSTextView?
        private var placeholderLabel: NSTextField?

        init(_ parent: GrowingTextInput) {
            self.parent = parent
            super.init()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            updatePlaceholder()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Return/Enter without shift = submit
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if !NSEvent.modifierFlags.contains(.shift) {
                    parent.onSubmit()
                    return true
                }
            }
            return false
        }

        func updatePlaceholder() {
            guard let textView = textView else { return }

            if placeholderLabel == nil {
                let label = NSTextField(labelWithString: parent.placeholder)
                label.textColor = .placeholderTextColor
                label.font = textView.font
                label.translatesAutoresizingMaskIntoConstraints = false
                label.isEditable = false
                label.isBordered = false
                label.drawsBackground = false
                textView.addSubview(label)

                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 8),
                    label.topAnchor.constraint(equalTo: textView.topAnchor, constant: 6)
                ])

                placeholderLabel = label
            }

            placeholderLabel?.isHidden = !textView.string.isEmpty
        }
    }
}

// MARK: - Conversation View

struct ConversationView: View {
    @EnvironmentObject var appState: AppState
    let conversationDetails: ConversationWithDetails
    @State private var newMessage = ""
    @State private var showDeleteConfirmation = false
    @State private var shouldScrollToBottom = false

    private var conversation: Conversation { conversationDetails.conversation }

    // Stable ID for scroll anchor at bottom
    private let bottomAnchorId = "bottom-anchor"

    var body: some View {
        VStack(spacing: 0) {
            // Header
            conversationHeader

            Divider()

            // Messages with proper scroll anchoring
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(appState.messages) { message in
                            MessageBubble(
                                message: message,
                                isFromCurrentUser: message.senderId == appState.currentUser?.id,
                                conversationMode: conversation.mode,
                                senderName: conversationDetails.participants.first { $0.id == message.senderId }?.displayName,
                                isAgentOnlyChat: conversationDetails.participants.allSatisfy { $0.isAgent || $0.id == appState.currentUser?.id }
                            )
                            .id(message.id)
                        }

                        // Invisible anchor at the very bottom
                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchorId)
                    }
                    .padding()
                }
                .onChange(of: appState.messages.count) { _, _ in
                    // Scroll when message count changes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(bottomAnchorId, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: shouldScrollToBottom) { _, shouldScroll in
                    if shouldScroll {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            proxy.scrollTo(bottomAnchorId, anchor: .bottom)
                            shouldScrollToBottom = false
                        }
                    }
                }
            }

            Divider()

            // Input
            messageInput
        }
        .task(id: conversationDetails.conversation.id) {
            await appState.loadMessages(for: conversationDetails)
            // Trigger scroll after messages load
            shouldScrollToBottom = true
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
            .accessibilityLabel("Refresh messages")

            // Delete button
            Button {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .help("Delete Conversation")
            .accessibilityLabel("Delete conversation")
            .accessibilityHint("Permanently deletes this conversation and all messages")
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
        HStack(alignment: .bottom, spacing: 12) {
            GrowingTextInput(placeholder: "Type a message...", text: $newMessage) {
                sendMessage()
            }
            .frame(minHeight: 28, maxHeight: 120)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            Button(action: sendMessage) {
                Image(systemName: "paperplane.fill")
                    .font(.title2)
            }
            .buttonStyle(.borderedProminent)
            .disabled(newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityLabel("Send message")
        }
        .padding()
    }

    func sendMessage() {
        let content = newMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        // Clear input immediately for responsive feel
        newMessage = ""

        Task {
            await appState.sendMessage(content: content, to: conversationDetails)
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
    let senderName: String?  // Name of sender (for agent messages)
    let isAgentOnlyChat: Bool  // True if no human recipients (agent messages don't get "processed")

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
    /// Only show if processed content exists AND is meaningfully different from raw content
    var showProcessedContent: Bool {
        guard let processed = message.contentProcessed,
              conversationMode == .assisted else { return false }

        // Don't show if it's just echoing the raw content
        let raw = message.contentRaw
        let normalizedProcessed = processed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedRaw = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return normalizedProcessed != normalizedRaw
    }

    /// Whether this message was AI-processed
    var wasProcessed: Bool {
        message.contentProcessed != nil
    }

    var body: some View {
        HStack {
            if isFromCurrentUser { Spacer() }

            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                // Sender indicator (show agent's name, not generic "AI Mediator")
                if message.isFromAgent {
                    Label(senderName ?? "AI", systemImage: "sparkles")
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
                    .textSelection(.enabled)

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
                // Only show for human-to-human chats where AI processing is expected
                if isFromCurrentUser && conversationMode != .direct && !isAgentOnlyChat {
                    HStack(spacing: 4) {
                        if wasProcessed {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("AI Processed")
                        } else {
                            Image(systemName: "checkmark")
                                .foregroundColor(.secondary)
                            Text("Sent")
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
