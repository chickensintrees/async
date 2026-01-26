import SwiftUI

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
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
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
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
            case .admin:
                AdminPortalView()
            }
        }
        .navigationSplitViewStyle(.balanced)
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
    @EnvironmentObject var gameVM: GamificationViewModel

    var body: some View {
        TabView {
            UserSettingsTab()
                .tabItem { Label("User", systemImage: "person") }

            APIKeysSettingsTab()
                .tabItem { Label("API Keys", systemImage: "key") }

            DashboardSettingsTab()
                .tabItem { Label("Dashboard", systemImage: "chart.bar") }

            DebugSettingsTab()
                .tabItem { Label("Debug", systemImage: "ant") }

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 500, height: 400)
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

struct APIKeysSettingsTab: View {
    @State private var anthropicKey: String = ""
    @State private var twilioAccountSID: String = ""
    @State private var twilioAuthToken: String = ""
    @State private var twilioPhoneNumber: String = ""
    @State private var showSaved = false
    @State private var isLoading = true

    var body: some View {
        Form {
            Section("Anthropic (AI Mediator)") {
                SecureField("API Key", text: $anthropicKey)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Circle()
                        .fill(anthropicKey.isEmpty ? Color.red : Color.green)
                        .frame(width: 8, height: 8)
                    Text(anthropicKey.isEmpty ? "Not configured" : "Configured")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Twilio (SMS Notifications)") {
                TextField("Account SID", text: $twilioAccountSID)
                    .textFieldStyle(.roundedBorder)

                SecureField("Auth Token", text: $twilioAuthToken)
                    .textFieldStyle(.roundedBorder)

                TextField("Phone Number (e.g. +14127648054)", text: $twilioPhoneNumber)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Circle()
                        .fill(twilioAccountSID.isEmpty ? Color.red : Color.green)
                        .frame(width: 8, height: 8)
                    Text(twilioAccountSID.isEmpty ? "Not configured" : "Configured")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section {
                HStack {
                    Button("Save") {
                        saveKeys()
                    }
                    .buttonStyle(.borderedProminent)

                    if showSaved {
                        Text("Saved!")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            loadKeys()
        }
    }

    func loadKeys() {
        let keys = APIKeyManager.shared.loadKeys()
        anthropicKey = keys.anthropic ?? ""
        twilioAccountSID = keys.twilioSID ?? ""
        twilioAuthToken = keys.twilioToken ?? ""
        twilioPhoneNumber = keys.twilioPhone ?? ""
        isLoading = false
    }

    func saveKeys() {
        APIKeyManager.shared.saveKeys(
            anthropic: anthropicKey.isEmpty ? nil : anthropicKey,
            twilioSID: twilioAccountSID.isEmpty ? nil : twilioAccountSID,
            twilioToken: twilioAuthToken.isEmpty ? nil : twilioAuthToken,
            twilioPhone: twilioPhoneNumber.isEmpty ? nil : twilioPhoneNumber
        )

        // Reload services with new keys
        MediatorService.shared.reloadAPIKey()
        TwilioService.shared.reloadCredentials()

        showSaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showSaved = false
        }
    }
}

// MARK: - API Key Manager

class APIKeyManager {
    static let shared = APIKeyManager()

    private let configPath: URL

    init() {
        // Store in app support directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let asyncDir = appSupport.appendingPathComponent("Async")
        try? FileManager.default.createDirectory(at: asyncDir, withIntermediateDirectories: true)
        configPath = asyncDir.appendingPathComponent("api-keys.json")
    }

    struct Keys: Codable {
        var anthropic: String?
        var twilioSID: String?
        var twilioToken: String?
        var twilioPhone: String?
    }

    func loadKeys() -> Keys {
        // First try app's own config
        if let data = try? Data(contentsOf: configPath),
           let keys = try? JSONDecoder().decode(Keys.self, from: data) {
            return keys
        }

        // Fall back to ~/.claude/config.json for anthropic key
        var keys = Keys()
        let claudeConfig = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/config.json")
        if let data = try? Data(contentsOf: claudeConfig),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let apiKeys = json["api_keys"] as? [String: Any] {
            keys.anthropic = apiKeys["anthropic"] as? String
        }

        return keys
    }

    func saveKeys(anthropic: String?, twilioSID: String?, twilioToken: String?, twilioPhone: String?) {
        let keys = Keys(
            anthropic: anthropic,
            twilioSID: twilioSID,
            twilioToken: twilioToken,
            twilioPhone: twilioPhone
        )

        if let data = try? JSONEncoder().encode(keys) {
            try? data.write(to: configPath)
        }
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

struct DebugSettingsTab: View {
    @EnvironmentObject var gameVM: GamificationViewModel
    @EnvironmentObject var dashboardVM: DashboardViewModel

    @State private var isSendingEmoji = false
    @State private var isSendingStatus = false
    @State private var emojiStatusMessage = ""
    @State private var statusStatusMessage = ""
    @State private var showEmojiStatus = false
    @State private var showStatusStatus = false

    private let jenniferPhone = "+14155316099"
    private let billPhone = "+14129659754"

    private let emojis = ["😀", "🎉", "🚀", "💜", "🔥", "✨", "🌈", "🦄", "🍕", "🎸",
                         "🌟", "💫", "🎯", "🏆", "💪", "🤖", "👾", "🎮", "🌮", "🍩"]

    var body: some View {
        Form {
            Section("Twilio SMS Test") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Send random emojis to Jennifer")
                        .font(.headline)

                    Text("Phone: \(jenniferPhone)")
                        .foregroundColor(.secondary)
                        .font(.caption)

                    Button(action: sendRandomEmojis) {
                        HStack {
                            if isSendingEmoji {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .padding(.trailing, 4)
                            }
                            Text(isSendingEmoji ? "Sending..." : "Send Random Emojis to Jennifer")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSendingEmoji)

                    if showEmojiStatus {
                        Text(emojiStatusMessage)
                            .font(.caption)
                            .foregroundColor(emojiStatusMessage.contains("Sent") ? .green : .red)
                            .padding(.top, 4)
                    }
                }
                .padding(.vertical, 8)
            }

            Section("Status Report") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Send dev status to Bill")
                        .font(.headline)

                    Text("Phone: \(billPhone)")
                        .foregroundColor(.secondary)
                        .font(.caption)

                    Button(action: sendStatusReport) {
                        HStack {
                            if isSendingStatus {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .padding(.trailing, 4)
                            }
                            Text(isSendingStatus ? "Sending..." : "Send Status Report to Bill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(isSendingStatus)

                    if showStatusStatus {
                        Text(statusStatusMessage)
                            .font(.caption)
                            .foregroundColor(statusStatusMessage.contains("Sent") ? .green : .red)
                            .padding(.top, 4)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    func sendRandomEmojis() {
        isSendingEmoji = true
        showEmojiStatus = false

        // Generate 3-5 random emojis
        let count = Int.random(in: 3...5)
        let randomEmojis = (0..<count).map { _ in emojis.randomElement()! }.joined()

        Task {
            do {
                try await TwilioService.shared.sendSMS(to: jenniferPhone, body: randomEmojis)
                await MainActor.run {
                    emojiStatusMessage = "Sent: \(randomEmojis)"
                    showEmojiStatus = true
                    isSendingEmoji = false
                }
            } catch {
                await MainActor.run {
                    emojiStatusMessage = "Error: \(error.localizedDescription)"
                    showEmojiStatus = true
                    isSendingEmoji = false
                }
            }
        }
    }

    func sendStatusReport() {
        isSendingStatus = true
        showStatusStatus = false

        Task {
            // Build status report
            let billScore = gameVM.gameState.players["chickensintrees"]?.totalScore ?? 0
            let noahScore = gameVM.gameState.players["ginzatron"]?.totalScore ?? 0
            let billTitle = gameVM.gameState.players["chickensintrees"]?.primaryTitle.name ?? "Keyboard Polisher"
            let noahTitle = gameVM.gameState.players["ginzatron"]?.primaryTitle.name ?? "Keyboard Polisher"

            let openIssues = dashboardVM.openIssueCount
            let recentCommits = dashboardVM.commits.prefix(3).map { $0.shortMessage }.joined(separator: ", ")

            let report = """
            📊 ASYNC STATUS

            🏆 SCORES
            Bill: \(billScore) (\(billTitle))
            Noah: \(noahScore) (\(noahTitle))

            📋 \(openIssues) open issues

            📝 Recent: \(recentCommits.isEmpty ? "No recent commits" : recentCommits)
            """

            do {
                try await TwilioService.shared.sendSMS(to: billPhone, body: report)
                await MainActor.run {
                    statusStatusMessage = "Sent status report!"
                    showStatusStatus = true
                    isSendingStatus = false
                }
            } catch {
                await MainActor.run {
                    statusStatusMessage = "Error: \(error.localizedDescription)"
                    showStatusStatus = true
                    isSendingStatus = false
                }
            }
        }
    }
}

// MARK: - Twilio Service

class TwilioService {
    static let shared = TwilioService()

    private var accountSID: String = ""
    private var authToken: String = ""
    private var fromNumber: String = ""

    init() {
        loadCredentials()
    }

    private func loadCredentials() {
        let keys = APIKeyManager.shared.loadKeys()
        accountSID = keys.twilioSID ?? ""
        authToken = keys.twilioToken ?? ""
        fromNumber = keys.twilioPhone ?? ""
    }

    func reloadCredentials() {
        loadCredentials()
    }

    func sendSMS(to: String, body: String) async throws {
        guard !accountSID.isEmpty, !authToken.isEmpty, !fromNumber.isEmpty else {
            throw TwilioError.notConfigured
        }

        let url = URL(string: "https://api.twilio.com/2010-04-01/Accounts/\(accountSID)/Messages.json")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // Basic auth
        let credentials = "\(accountSID):\(authToken)"
        let base64Credentials = Data(credentials.utf8).base64EncodedString()
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Form body
        let params = [
            "To": to,
            "From": fromNumber,
            "Body": body
        ]
        let bodyString = params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TwilioError.invalidResponse
        }

        if httpResponse.statusCode >= 400 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TwilioError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
    }

    enum TwilioError: LocalizedError {
        case notConfigured
        case invalidResponse
        case apiError(statusCode: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Twilio not configured. Add credentials in Settings > API Keys."
            case .invalidResponse:
                return "Invalid response from Twilio"
            case .apiError(let statusCode, let message):
                return "Twilio error (\(statusCode)): \(message)"
            }
        }
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
