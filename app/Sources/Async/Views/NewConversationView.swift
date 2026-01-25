import SwiftUI

struct NewConversationView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var recipientHandle = ""
    @State private var title = ""
    @State private var selectedMode: ConversationMode = .assisted
    @State private var foundUser: User?
    @State private var isSearching = false
    @State private var searchError: String?
    @FocusState private var isRecipientFocused: Bool

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

            Form {
                // Recipient
                Section("Recipient") {
                    HStack {
                        TextField("GitHub username", text: $recipientHandle)
                            .textFieldStyle(.squareBorder)
                            .focused($isRecipientFocused)

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

                    // Quick select for ginzatron
                    Button("Select ginzatron") {
                        recipientHandle = "ginzatron"
                        searchUser()
                    }
                    .buttonStyle(.link)
                }

                // Title
                Section("Conversation Title (Optional)") {
                    TextField("e.g., Project Discussion", text: $title)
                        .textFieldStyle(.squareBorder)
                }

                // Mode
                Section("Communication Mode") {
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

                    // Mode explanation
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("About this mode", systemImage: "info.circle")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text(selectedMode.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .padding()

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
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isRecipientFocused = true
            }
        }
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
