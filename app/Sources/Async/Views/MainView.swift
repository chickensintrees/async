import SwiftUI

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var dashboardVM: DashboardViewModel

    var body: some View {
        NavigationSplitView {
            // Main navigation sidebar
            List(selection: $appState.selectedTab) {
                Section("App") {
                    ForEach(AppTab.allCases, id: \.self) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 150)
        } detail: {
            switch appState.selectedTab {
            case .messages:
                MessagesView()
            case .contacts:
                ContactsView()
            case .dashboard:
                DashboardView()
            case .backlog:
                BacklogView()
            }
        }
        .task {
            await appState.loadOrCreateUser(
                githubHandle: Config.currentUserGithubHandle,
                displayName: Config.currentUserDisplayName
            )
            await appState.loadConversations()
        }
        .sheet(isPresented: $appState.showNewConversation) {
            NewConversationView()
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

// MARK: - Messages View (wraps existing conversation UI)

struct MessagesView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            ConversationListView()
        } detail: {
            if let conversation = appState.selectedConversation {
                ConversationView(conversation: conversation)
            } else {
                MessagesWelcomeView()
            }
        }
    }
}

struct ConversationListView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List(selection: $appState.selectedConversation) {
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
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .toolbar {
            ToolbarItem {
                Button(action: { appState.showNewConversation = true }) {
                    Image(systemName: "plus")
                }
                .help("New Conversation")
            }
        }
        .navigationTitle("Conversations")
    }
}

struct MessagesWelcomeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "message.badge.waveform")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("Messages")
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

            Button("New Conversation") {
                appState.showNewConversation = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Backlog View

struct BacklogView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @State private var backlogIssues: [BacklogIssue] = []
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "list.bullet.rectangle")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("Product Backlog")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                Text("\(backlogIssues.count) items")
                    .foregroundColor(.secondary)

                Button(action: loadBacklog) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            if isLoading {
                ProgressView("Loading backlog...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if backlogIssues.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No backlog items")
                        .font(.headline)
                    Text("Create issues with the 'backlog' label on GitHub")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(backlogIssues) { issue in
                    BacklogIssueRow(issue: issue)
                }
            }
        }
        .task {
            loadBacklog()
        }
    }

    func loadBacklog() {
        isLoading = true
        Task {
            do {
                backlogIssues = try await GitHubService.shared.fetchBacklogIssues()
            } catch {
                print("Failed to load backlog: \(error)")
            }
            isLoading = false
        }
    }
}

struct BacklogIssue: Identifiable, Codable {
    let id: Int
    let number: Int
    let title: String
    let state: String
    let labels: [IssueLabel]
    let html_url: String
    let created_at: Date

    var storyPoints: Int? {
        for label in labels {
            if label.name.hasPrefix("story-points:") {
                return Int(label.name.replacingOccurrences(of: "story-points:", with: ""))
            }
        }
        return nil
    }

    var isHighPriority: Bool {
        labels.contains { $0.name == "priority:high" }
    }

    struct IssueLabel: Codable {
        let name: String
        let color: String
    }
}

struct BacklogIssueRow: View {
    let issue: BacklogIssue

    var body: some View {
        HStack(spacing: 12) {
            // Priority indicator
            if issue.isHighPriority {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            }

            // Issue number
            Text("#\(issue.number)")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)

            // Title
            Text(issue.title)
                .lineLimit(1)

            Spacer()

            // Story points
            if let points = issue.storyPoints {
                Text("\(points) pts")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(4)
            }

            // Status
            Circle()
                .fill(issue.state == "open" ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = URL(string: issue.html_url) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

// MARK: - Unified Settings

struct UnifiedSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var dashboardVM: DashboardViewModel

    var body: some View {
        TabView {
            UserSettingsTab()
                .tabItem { Label("User", systemImage: "person") }

            DashboardSettingsTab()
                .tabItem { Label("Dashboard", systemImage: "chart.bar") }

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 450, height: 300)
    }
}

struct UserSettingsTab: View {
    var body: some View {
        Form {
            Section("User Profile") {
                LabeledContent("GitHub", value: Config.currentUserGithubHandle)
                LabeledContent("Display Name", value: Config.currentUserDisplayName)
            }

            Section("Connection") {
                LabeledContent("Supabase", value: "Connected")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct DashboardSettingsTab: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel

    var body: some View {
        Form {
            Section("Polling Intervals") {
                HStack {
                    Text("Commits")
                    Spacer()
                    Text("\(Int(dashboardVM.commitInterval))s")
                    Slider(value: $dashboardVM.commitInterval, in: 30...120, step: 10)
                        .frame(width: 150)
                }
                HStack {
                    Text("Issues")
                    Spacer()
                    Text("\(Int(dashboardVM.issueInterval))s")
                    Slider(value: $dashboardVM.issueInterval, in: 15...60, step: 5)
                        .frame(width: 150)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "message.badge.waveform")
                .font(.system(size: 48))
                .foregroundColor(.blue)

            Text("Async")
                .font(.title)
                .fontWeight(.bold)

            Text("AI-Mediated Asynchronous Messaging")
                .foregroundColor(.secondary)

            Text("Version 0.1.0")
                .font(.caption)

            Link("GitHub Repository", destination: URL(string: "https://github.com/chickensintrees/async")!)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
