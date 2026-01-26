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
    let conversation: Conversation
    @State private var newMessage = ""

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
            await appState.loadMessages(for: conversation)
        }
        .onChange(of: conversation) { _, newConvo in
            Task {
                await appState.loadMessages(for: newConvo)
            }
        }
    }

    var conversationHeader: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(conversation.displayTitle)
                    .font(.headline)
                HStack(spacing: 4) {
                    modeIcon
                    Text(conversation.mode.displayName)
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: {
                Task { await appState.loadMessages(for: conversation) }
            }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh messages")
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    var modeIcon: some View {
        Group {
            switch conversation.mode {
            case .anonymous:
                Image(systemName: "eye.slash")
                    .foregroundColor(.purple)
            case .assisted:
                Image(systemName: "person.2.wave.2")
                    .foregroundColor(.blue)
            case .direct:
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundColor(.green)
            }
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
            await appState.sendMessage(content: content, to: conversation)
            newMessage = ""
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: Message
    let isFromCurrentUser: Bool
    let conversationMode: ConversationMode

    var body: some View {
        HStack {
            if isFromCurrentUser { Spacer() }

            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                // Sender indicator
                if message.isFromAgent {
                    Label("AI Agent", systemImage: "cpu")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }

                // Message content
                Text(message.contentRaw)
                    .padding(12)
                    .background(isFromCurrentUser ? Color.blue : Color(nsColor: .controlBackgroundColor))
                    .foregroundColor(isFromCurrentUser ? .white : .primary)
                    .cornerRadius(16)

                // AI processed version (if available and in assisted mode)
                if conversationMode == .assisted, let processed = message.contentProcessed {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                        Text(processed)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                }

                // Timestamp
                Text(message.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if !isFromCurrentUser { Spacer() }
        }
    }
}
