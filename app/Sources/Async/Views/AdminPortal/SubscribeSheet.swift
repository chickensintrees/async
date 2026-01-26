import SwiftUI

struct SubscribeSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var githubHandle = ""
    @State private var message = ""
    @State private var isSearching = false
    @State private var foundUser: User?
    @State private var searchError: String?
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("GitHub username", text: $githubHandle)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                searchUser()
                            }

                        Button(action: searchUser) {
                            if isSearching {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "magnifyingglass")
                            }
                        }
                        .disabled(githubHandle.isEmpty || isSearching)
                    }
                } header: {
                    Text("Find User")
                } footer: {
                    Text("Enter the GitHub username of the person you want to subscribe to.")
                }

                if let error = searchError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                if let user = foundUser {
                    Section("User Found") {
                        HStack(spacing: 12) {
                            // Avatar
                            Group {
                                if let avatarUrl = user.avatarUrl, let url = URL(string: avatarUrl) {
                                    AsyncImage(url: url) { image in
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        userPlaceholder(for: user)
                                    }
                                } else {
                                    userPlaceholder(for: user)
                                }
                            }
                            .frame(width: 50, height: 50)
                            .clipShape(Circle())

                            VStack(alignment: .leading) {
                                Text(user.displayName)
                                    .font(.headline)
                                if let handle = user.githubHandle {
                                    Text("@\(handle)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }

                    Section {
                        TextEditor(text: $message)
                            .frame(minHeight: 80)
                    } header: {
                        Text("Message (Optional)")
                    } footer: {
                        Text("Include a message with your subscription request.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Subscribe to User")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Subscribe") {
                        submitRequest()
                    }
                    .disabled(foundUser == nil || isSubmitting)
                }
            }
        }
        .frame(width: 450, height: 400)
    }

    private func userPlaceholder(for user: User) -> some View {
        ZStack {
            Circle()
                .fill(Color.gray.opacity(0.2))
            Text(user.displayName.prefix(1).uppercased())
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private func searchUser() {
        guard !githubHandle.isEmpty else { return }

        isSearching = true
        searchError = nil
        foundUser = nil

        Task {
            let user = await appState.findUser(byGithubHandle: githubHandle)

            await MainActor.run {
                isSearching = false
                if let user = user {
                    // Check if this is the current user
                    if user.id == appState.currentUser?.id {
                        searchError = "You can't subscribe to yourself."
                    }
                    // Check if already subscribed
                    else if appState.subscriptions.contains(where: { $0.connection.ownerId == user.id }) {
                        searchError = "You're already subscribed to this user."
                    } else {
                        foundUser = user
                    }
                } else {
                    searchError = "User not found. They must sign up first."
                }
            }
        }
    }

    private func submitRequest() {
        guard let user = foundUser else { return }

        isSubmitting = true

        Task {
            let success = await appState.createSubscription(
                toUserId: user.id,
                message: message.isEmpty ? nil : message
            )

            await MainActor.run {
                isSubmitting = false
                if success {
                    dismiss()
                }
            }
        }
    }
}
