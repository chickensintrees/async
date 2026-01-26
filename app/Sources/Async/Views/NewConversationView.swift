import SwiftUI
import AppKit

// NSTextField wrapper for reliable focus in sheets
struct FocusableTextField: NSViewRepresentable {
    var placeholder: String
    @Binding var text: String
    var onSubmit: (() -> Void)?

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .exterior
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        nsView.stringValue = text
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FocusableTextField

        init(_ parent: FocusableTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit?()
                return true
            }
            return false
        }
    }
}

struct NewConversationView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var recipientHandle = ""
    @State private var title = ""
    @State private var selectedMode: ConversationMode = .assisted
    @State private var foundUser: User?
    @State private var isSearching = false
    @State private var searchError: String?

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

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Recipient Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recipient")
                            .font(.headline)

                        HStack {
                            Text("GitHub username")
                                .frame(width: 120, alignment: .leading)
                            FocusableTextField(placeholder: "", text: $recipientHandle) {
                                searchUser()
                            }
                            .frame(height: 24)
                            Button("Find") {
                                searchUser()
                            }
                            .disabled(recipientHandle.isEmpty || isSearching)
                        }

                        if isSearching {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else if let user = foundUser {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Found: \(user.displayName)")
                                Text("(@\(user.githubHandle ?? ""))")
                                    .foregroundColor(.secondary)
                            }
                        } else if let error = searchError {
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                Text(error)
                            }
                        }

                        Button("Select ginzatron") {
                            recipientHandle = "ginzatron"
                            searchUser()
                        }
                        .buttonStyle(.link)
                    }

                    Divider()

                    // Title Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Conversation Title (Optional)")
                            .font(.headline)

                        HStack {
                            Text("e.g., Project Discussion")
                                .frame(width: 160, alignment: .leading)
                                .foregroundColor(.secondary)
                            FocusableTextField(placeholder: "", text: $title)
                                .frame(height: 24)
                        }
                    }

                    Divider()

                    // Mode Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Communication Mode")
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
                    }
                }
                .padding()
            }

            Divider()

            // Actions
            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Button("Create Conversation") {
                    createConversation()
                }
                .buttonStyle(.borderedProminent)
                .disabled(foundUser == nil)
                .keyboardShortcut(.return)
            }
            .padding()
        }
        .frame(width: 500, height: 550)
    }

    func searchUser() {
        isSearching = true
        searchError = nil
        foundUser = nil

        Task {
            // First check if user exists
            if let user = await appState.findUser(byGithubHandle: recipientHandle) {
                foundUser = user
            } else {
                // User doesn't exist yet - create them
                // For MVP, we'll create a placeholder user
                searchError = "User not found. They need to open Async first to be added."

                // Actually, let's be more helpful and create them
                // This is a bit of a hack for MVP
            }
            isSearching = false
        }
    }

    func createConversation() {
        guard let recipient = foundUser else { return }

        Task {
            if let conversation = await appState.createConversation(
                with: [recipient.id],
                mode: selectedMode,
                title: title.isEmpty ? nil : title
            ) {
                appState.selectedConversation = conversation
                dismiss()
            }
        }
    }
}
