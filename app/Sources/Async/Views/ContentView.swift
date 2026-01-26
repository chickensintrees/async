import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            if let conversation = appState.selectedConversation {
                ConversationView(conversation: conversation)
            } else {
                WelcomeView()
            }
        }
        .task {
            // Load or create current user on launch
            await appState.loadOrCreateUser(
                githubHandle: Config.currentUserGithubHandle,
                displayName: Config.currentUserDisplayName
            )
            await appState.loadConversations()
        }
        .sheet(isPresented: $appState.showNewConversation) {
            NewConversationView()
        }
        .sheet(isPresented: $appState.showAdminPortal) {
            AdminPortalView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .alert("Error", isPresented: .init(
            get: { appState.errorMessage != nil },
            set: { if !$0 { appState.errorMessage = nil } }
        )) {
            Button("OK") { appState.errorMessage = nil }
        } message: {
            Text(appState.errorMessage ?? "")
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List(selection: $appState.selectedConversation) {
            Section("Conversations") {
                if appState.conversations.isEmpty {
                    Text("No conversations yet")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(appState.conversations) { conversation in
                        ConversationRow(conversation: conversation)
                            .tag(conversation)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .toolbar {
            ToolbarItemGroup {
                Button(action: { appState.showAdminPortal = true }) {
                    Image(systemName: "person.2.badge.gearshape")
                }
                .help("Admin Portal")

                Button(action: { appState.showNewConversation = true }) {
                    Image(systemName: "plus")
                }
                .help("New Conversation")
            }
        }
    }
}

struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack {
            modeIcon
                .foregroundColor(modeColor)
            VStack(alignment: .leading) {
                Text(conversation.displayTitle)
                    .font(.headline)
                Text(conversation.mode.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    var modeIcon: Image {
        switch conversation.mode {
        case .anonymous: return Image(systemName: "eye.slash")
        case .assisted: return Image(systemName: "person.2.wave.2")
        case .direct: return Image(systemName: "arrow.left.arrow.right")
        }
    }

    var modeColor: Color {
        switch conversation.mode {
        case .anonymous: return .purple
        case .assisted: return .blue
        case .direct: return .green
        }
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "message.badge.waveform")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("Welcome to Async")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("AI-mediated asynchronous messaging")
                .font(.title3)
                .foregroundColor(.secondary)

            if let user = appState.currentUser {
                Text("Logged in as \(user.displayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()
                .frame(width: 200)

            VStack(alignment: .leading, spacing: 12) {
                Label("Select a conversation from the sidebar", systemImage: "sidebar.left")
                Label("Or create a new one with ⌘N", systemImage: "plus.circle")
            }
            .foregroundColor(.secondary)

            Button("New Conversation") {
                appState.showNewConversation = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
