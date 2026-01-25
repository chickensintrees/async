import SwiftUI
import Foundation
import AppKit

// MARK: - App Entry Point

@main
struct AsyncDashboardApp: App {
    @StateObject private var viewModel = DashboardViewModel()

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(viewModel)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 900, height: 650)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            SettingsView()
                .environmentObject(viewModel)
        }
    }
}

// MARK: - Design Tokens

enum DesignTokens {
    // Backgrounds
    static let bgPrimary = Color(red: 0.06, green: 0.06, blue: 0.09)
    static let bgSecondary = Color(red: 0.10, green: 0.10, blue: 0.14)
    static let bgTertiary = Color(red: 0.14, green: 0.14, blue: 0.18)
    static let bgElevated = Color(red: 0.12, green: 0.12, blue: 0.16)

    // Accent Colors (GitHub-inspired)
    static let accentPrimary = Color(red: 0.35, green: 0.55, blue: 0.98)
    static let accentGreen = Color(red: 0.24, green: 0.74, blue: 0.46)
    static let accentPurple = Color(red: 0.64, green: 0.45, blue: 0.90)
    static let accentOrange = Color(red: 0.95, green: 0.55, blue: 0.25)
    static let accentRed = Color(red: 0.90, green: 0.35, blue: 0.40)
    static let accentYellow = Color(red: 0.95, green: 0.80, blue: 0.25)

    // Text
    static let textPrimary = Color.white.opacity(0.95)
    static let textSecondary = Color.white.opacity(0.65)
    static let textTertiary = Color.white.opacity(0.45)
    static let textMuted = Color.white.opacity(0.30)

    // Status
    static let statusSuccess = accentGreen
    static let statusPending = accentYellow
    static let statusFailure = accentRed
    static let statusNeutral = textSecondary

    // Spacing (8px grid)
    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 12
    static let spacingLG: CGFloat = 16
    static let spacingXL: CGFloat = 24
    static let spacingXXL: CGFloat = 32

    // Corner Radius
    static let radiusSM: CGFloat = 4
    static let radiusMD: CGFloat = 8
    static let radiusLG: CGFloat = 12
    static let radiusXL: CGFloat = 16

    // Typography
    static let fontTitle = Font.system(size: 20, weight: .bold)
    static let fontHeadline = Font.system(size: 16, weight: .semibold)
    static let fontBody = Font.system(size: 14, weight: .regular)
    static let fontCaption = Font.system(size: 12, weight: .regular)
    static let fontMono = Font.system(size: 12, weight: .regular, design: .monospaced)
}

// MARK: - User Colors

enum UserColors {
    static func forUser(_ username: String) -> Color {
        switch username.lowercased() {
        case "chickensintrees": return DesignTokens.accentPrimary
        case "ginzatron": return DesignTokens.accentPurple
        default: return DesignTokens.textSecondary
        }
    }

    static func initial(for username: String) -> String {
        switch username.lowercased() {
        case "chickensintrees": return "B"
        case "ginzatron": return "N"
        default: return String(username.prefix(1)).uppercased()
        }
    }
}

// MARK: - Data Models

struct Commit: Codable, Identifiable {
    let sha: String
    let commit: CommitDetail
    let author: GitHubUser?
    let html_url: String

    var id: String { sha }
    var shortSha: String { String(sha.prefix(7)) }
    var shortMessage: String { commit.message.components(separatedBy: "\n").first ?? commit.message }
    var authorLogin: String { author?.login ?? commit.author.name }
    var date: Date { commit.author.date }

    struct CommitDetail: Codable {
        let message: String
        let author: CommitAuthor
    }

    struct CommitAuthor: Codable {
        let name: String
        let date: Date
    }
}

struct GitHubUser: Codable {
    let login: String
    let avatar_url: String?
}

struct Issue: Codable, Identifiable {
    let number: Int
    let title: String
    let state: String
    let user: GitHubUser
    let created_at: Date
    let updated_at: Date
    let labels: [Label]
    let comments: Int
    let html_url: String
    let pull_request: PullRequestRef?

    var id: Int { number }
    var isOpen: Bool { state == "open" }
    var isPullRequest: Bool { pull_request != nil }

    struct Label: Codable {
        let name: String
        let color: String
    }

    struct PullRequestRef: Codable {
        let url: String
    }
}

struct PullRequest: Codable, Identifiable {
    let number: Int
    let title: String
    let state: String
    let draft: Bool
    let user: GitHubUser
    let created_at: Date
    let updated_at: Date
    let head: Branch
    let base: Branch
    let additions: Int?
    let deletions: Int?
    let html_url: String
    let merged_at: Date?

    var id: Int { number }
    var isOpen: Bool { state == "open" }
    var isMerged: Bool { merged_at != nil }

    struct Branch: Codable {
        let ref: String
    }
}

struct WorkflowRun: Codable, Identifiable {
    let id: Int
    let name: String
    let status: String
    let conclusion: String?
    let created_at: Date
    let head_sha: String
    let head_branch: String
    let html_url: String

    var shortSha: String { String(head_sha.prefix(7)) }
    var isRunning: Bool { status == "in_progress" || status == "queued" }
    var isSuccess: Bool { conclusion == "success" }
    var isFailure: Bool { conclusion == "failure" }
}

struct WorkflowRunsResponse: Codable {
    let workflow_runs: [WorkflowRun]
}

struct RepoEvent: Codable, Identifiable {
    let id: String
    let type: String
    let actor: Actor
    let created_at: Date
    let payload: Payload?

    struct Actor: Codable {
        let login: String
    }

    struct Payload: Codable {
        let action: String?
        let ref: String?
        let ref_type: String?
        let commits: [PushCommit]?
        let issue: Issue?
        let pull_request: PullRequest?

        struct PushCommit: Codable {
            let sha: String
            let message: String
        }
    }

    var description: String {
        switch type {
        case "PushEvent":
            let count = payload?.commits?.count ?? 0
            let branch = payload?.ref?.replacingOccurrences(of: "refs/heads/", with: "") ?? "main"
            return "pushed \(count) commit\(count == 1 ? "" : "s") to \(branch)"
        case "IssuesEvent":
            let action = payload?.action ?? "updated"
            let num = payload?.issue?.number ?? 0
            return "\(action) issue #\(num)"
        case "PullRequestEvent":
            let action = payload?.action ?? "updated"
            let num = payload?.pull_request?.number ?? 0
            return "\(action) PR #\(num)"
        case "IssueCommentEvent":
            let num = payload?.issue?.number ?? 0
            return "commented on #\(num)"
        case "CreateEvent":
            let refType = payload?.ref_type ?? "branch"
            let ref = payload?.ref ?? ""
            return "created \(refType) \(ref)"
        case "DeleteEvent":
            let refType = payload?.ref_type ?? "branch"
            let ref = payload?.ref ?? ""
            return "deleted \(refType) \(ref)"
        case "MemberEvent":
            return "joined as collaborator"
        default:
            return type.replacingOccurrences(of: "Event", with: "").lowercased()
        }
    }
}

// MARK: - GitHub Service

class GitHubService {
    static let shared = GitHubService()

    private let ghPath: String
    private let repo = "chickensintrees/async"

    init() {
        ghPath = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
            .first { FileManager.default.fileExists(atPath: $0) } ?? "gh"
    }

    func fetch<T: Decodable>(_ endpoint: String) async throws -> T {
        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: ghPath)
        process.arguments = ["api", endpoint]
        process.standardOutput = pipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "GitHubService", code: Int(process.terminationStatus),
                         userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(T.self, from: data)
    }

    func fetchCommits() async throws -> [Commit] {
        try await fetch("repos/\(repo)/commits?per_page=10")
    }

    func fetchIssues() async throws -> [Issue] {
        let issues: [Issue] = try await fetch("repos/\(repo)/issues?state=all&per_page=15")
        return issues.filter { !$0.isPullRequest }
    }

    func fetchPullRequests() async throws -> [PullRequest] {
        try await fetch("repos/\(repo)/pulls?state=all&per_page=10")
    }

    func fetchWorkflows() async throws -> [WorkflowRun] {
        let response: WorkflowRunsResponse = try await fetch("repos/\(repo)/actions/runs?per_page=10")
        return response.workflow_runs
    }

    func fetchEvents() async throws -> [RepoEvent] {
        try await fetch("repos/\(repo)/events?per_page=20")
    }

    func checkAuth() async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ghPath)
        process.arguments = ["auth", "status"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

// MARK: - Dashboard View Model

@MainActor
class DashboardViewModel: ObservableObject {
    @Published var commits: [Commit] = []
    @Published var issues: [Issue] = []
    @Published var pullRequests: [PullRequest] = []
    @Published var workflows: [WorkflowRun] = []
    @Published var events: [RepoEvent] = []

    @Published var isLoading: Bool = false
    @Published var isConnected: Bool = false
    @Published var lastRefresh: Date?
    @Published var error: String?

    // Polling intervals (seconds)
    @Published var commitInterval: Double = 60
    @Published var issueInterval: Double = 30
    @Published var prInterval: Double = 30
    @Published var workflowInterval: Double = 45
    @Published var eventInterval: Double = 30

    private var tasks: [String: Task<Void, Never>] = [:]
    private let service = GitHubService.shared

    var openIssueCount: Int { issues.filter { $0.isOpen }.count }
    var openPRCount: Int { pullRequests.filter { $0.isOpen }.count }

    init() {
        Task {
            await checkConnection()
            await refreshAll()
            startPolling()
        }
    }

    func checkConnection() async {
        isConnected = await service.checkAuth()
    }

    func startPolling() {
        schedulePolling("commits", interval: commitInterval) { [weak self] in
            await self?.fetchCommits()
        }
        schedulePolling("issues", interval: issueInterval) { [weak self] in
            await self?.fetchIssues()
        }
        schedulePolling("prs", interval: prInterval) { [weak self] in
            await self?.fetchPullRequests()
        }
        schedulePolling("workflows", interval: workflowInterval) { [weak self] in
            await self?.fetchWorkflows()
        }
        schedulePolling("events", interval: eventInterval) { [weak self] in
            await self?.fetchEvents()
        }
    }

    private func schedulePolling(_ key: String, interval: Double, action: @escaping () async -> Void) {
        tasks[key]?.cancel()
        tasks[key] = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                await action()
            }
        }
    }

    func refreshAll() async {
        isLoading = true
        error = nil

        async let c: () = fetchCommits()
        async let i: () = fetchIssues()
        async let p: () = fetchPullRequests()
        async let w: () = fetchWorkflows()
        async let e: () = fetchEvents()

        _ = await (c, i, p, w, e)

        lastRefresh = Date()
        isLoading = false
    }

    func fetchCommits() async {
        do {
            commits = try await service.fetchCommits()
        } catch {
            self.error = "Commits: \(error.localizedDescription)"
        }
    }

    func fetchIssues() async {
        do {
            issues = try await service.fetchIssues()
        } catch {
            self.error = "Issues: \(error.localizedDescription)"
        }
    }

    func fetchPullRequests() async {
        do {
            pullRequests = try await service.fetchPullRequests()
        } catch {
            self.error = "PRs: \(error.localizedDescription)"
        }
    }

    func fetchWorkflows() async {
        do {
            workflows = try await service.fetchWorkflows()
        } catch {
            // Actions might not be set up, don't show error
        }
    }

    func fetchEvents() async {
        do {
            events = try await service.fetchEvents()
        } catch {
            self.error = "Events: \(error.localizedDescription)"
        }
    }

    func openInBrowser(_ url: String) {
        if let url = URL(string: url) {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Main Dashboard View

struct DashboardView: View {
    @EnvironmentObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()

            HSplitView {
                LeftColumn()
                    .frame(minWidth: 350)
                RightColumn()
                    .frame(minWidth: 400)
            }
        }
        .background(DesignTokens.bgPrimary)
    }
}

// MARK: - Header View

struct HeaderView: View {
    @EnvironmentObject var viewModel: DashboardViewModel

    var body: some View {
        HStack(spacing: DesignTokens.spacingMD) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 20))
                .foregroundColor(DesignTokens.accentPrimary)

            Text("chickensintrees/async")
                .font(DesignTokens.fontTitle)
                .foregroundColor(DesignTokens.textPrimary)

            Button(action: {
                viewModel.openInBrowser("https://github.com/chickensintrees/async")
            }) {
                Image(systemName: "arrow.up.right.square")
                    .foregroundColor(DesignTokens.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: DesignTokens.spacingSM) {
                Circle()
                    .fill(viewModel.isConnected ? DesignTokens.statusSuccess : DesignTokens.statusFailure)
                    .frame(width: 8, height: 8)
                Text(viewModel.isConnected ? "Connected" : "Disconnected")
                    .font(DesignTokens.fontCaption)
                    .foregroundColor(DesignTokens.textSecondary)
            }

            if let lastRefresh = viewModel.lastRefresh {
                Text("Updated \(lastRefresh.relativeString)")
                    .font(DesignTokens.fontCaption)
                    .foregroundColor(DesignTokens.textMuted)
            }

            Button(action: {
                Task { await viewModel.refreshAll() }
            }) {
                Image(systemName: viewModel.isLoading ? "arrow.clockwise" : "arrow.clockwise")
                    .rotationEffect(.degrees(viewModel.isLoading ? 360 : 0))
                    .animation(viewModel.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: viewModel.isLoading)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isLoading)
        }
        .padding(DesignTokens.spacingLG)
        .background(DesignTokens.bgSecondary)
    }
}

// MARK: - Left Column

struct LeftColumn: View {
    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.spacingLG) {
                ActivityFeedPanel()
                CommitsPanel()
            }
            .padding(DesignTokens.spacingLG)
        }
    }
}

// MARK: - Right Column

struct RightColumn: View {
    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.spacingLG) {
                IssuesPanel()
                PullRequestsPanel()
                WorkflowsPanel()
            }
            .padding(DesignTokens.spacingLG)
        }
    }
}

// MARK: - Panel Component

struct DashboardPanel<Content: View>: View {
    let title: String
    let icon: String
    let badgeCount: Int?
    let content: () -> Content

    init(title: String, icon: String, badgeCount: Int? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.badgeCount = badgeCount
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(DesignTokens.textSecondary)
                Text(title)
                    .font(DesignTokens.fontHeadline)
                    .foregroundColor(DesignTokens.textPrimary)

                if let count = badgeCount, count > 0 {
                    Text("\(count)")
                        .font(DesignTokens.fontCaption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DesignTokens.accentPrimary)
                        .cornerRadius(DesignTokens.radiusSM)
                }

                Spacer()
            }

            content()
        }
        .padding(DesignTokens.spacingMD)
        .background(DesignTokens.bgSecondary)
        .cornerRadius(DesignTokens.radiusLG)
    }
}

// MARK: - Activity Feed Panel

struct ActivityFeedPanel: View {
    @EnvironmentObject var viewModel: DashboardViewModel

    var body: some View {
        DashboardPanel(title: "Activity Feed", icon: "bolt.fill") {
            if viewModel.events.isEmpty {
                Text("No recent activity")
                    .font(DesignTokens.fontBody)
                    .foregroundColor(DesignTokens.textMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                VStack(spacing: DesignTokens.spacingXS) {
                    ForEach(viewModel.events.prefix(10)) { event in
                        EventRow(event: event)
                    }
                }
            }
        }
    }
}

struct EventRow: View {
    let event: RepoEvent

    var body: some View {
        HStack(spacing: DesignTokens.spacingSM) {
            UserIndicator(username: event.actor.login)

            Text(event.description)
                .font(DesignTokens.fontBody)
                .foregroundColor(DesignTokens.textPrimary)
                .lineLimit(1)

            Spacer()

            Text(event.created_at.relativeString)
                .font(DesignTokens.fontCaption)
                .foregroundColor(DesignTokens.textMuted)
        }
        .padding(.vertical, DesignTokens.spacingXS)
    }
}

// MARK: - Commits Panel

struct CommitsPanel: View {
    @EnvironmentObject var viewModel: DashboardViewModel

    var body: some View {
        DashboardPanel(title: "Recent Commits", icon: "arrow.triangle.merge") {
            if viewModel.commits.isEmpty {
                Text("No commits yet")
                    .font(DesignTokens.fontBody)
                    .foregroundColor(DesignTokens.textMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                VStack(spacing: DesignTokens.spacingXS) {
                    ForEach(viewModel.commits.prefix(8)) { commit in
                        CommitRow(commit: commit)
                    }
                }
            }
        }
    }
}

struct CommitRow: View {
    @EnvironmentObject var viewModel: DashboardViewModel
    let commit: Commit

    var body: some View {
        Button(action: {
            viewModel.openInBrowser(commit.html_url)
        }) {
            HStack(spacing: DesignTokens.spacingSM) {
                Text(commit.shortSha)
                    .font(DesignTokens.fontMono)
                    .foregroundColor(DesignTokens.accentPrimary)

                Text(commit.shortMessage)
                    .font(DesignTokens.fontBody)
                    .foregroundColor(DesignTokens.textPrimary)
                    .lineLimit(1)

                Spacer()

                UserIndicator(username: commit.authorLogin)

                Text(commit.date.relativeString)
                    .font(DesignTokens.fontCaption)
                    .foregroundColor(DesignTokens.textMuted)
            }
            .padding(.vertical, DesignTokens.spacingXS)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Issues Panel

struct IssuesPanel: View {
    @EnvironmentObject var viewModel: DashboardViewModel

    var body: some View {
        DashboardPanel(title: "Issues", icon: "exclamationmark.circle", badgeCount: viewModel.openIssueCount) {
            if viewModel.issues.isEmpty {
                Text("No issues")
                    .font(DesignTokens.fontBody)
                    .foregroundColor(DesignTokens.textMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                VStack(spacing: DesignTokens.spacingXS) {
                    ForEach(viewModel.issues.prefix(8)) { issue in
                        IssueRow(issue: issue)
                    }
                }
            }
        }
    }
}

struct IssueRow: View {
    @EnvironmentObject var viewModel: DashboardViewModel
    let issue: Issue

    var body: some View {
        Button(action: {
            viewModel.openInBrowser(issue.html_url)
        }) {
            HStack(spacing: DesignTokens.spacingSM) {
                StatusDot(isOpen: issue.isOpen)

                Text("#\(issue.number)")
                    .font(DesignTokens.fontMono)
                    .foregroundColor(DesignTokens.textSecondary)

                Text(issue.title)
                    .font(DesignTokens.fontBody)
                    .foregroundColor(DesignTokens.textPrimary)
                    .lineLimit(1)

                ForEach(issue.labels.prefix(2), id: \.name) { label in
                    LabelPill(label: label)
                }

                Spacer()

                if issue.comments > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "bubble.left")
                        Text("\(issue.comments)")
                    }
                    .font(DesignTokens.fontCaption)
                    .foregroundColor(DesignTokens.textMuted)
                }

                UserIndicator(username: issue.user.login)
            }
            .padding(.vertical, DesignTokens.spacingXS)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pull Requests Panel

struct PullRequestsPanel: View {
    @EnvironmentObject var viewModel: DashboardViewModel

    var body: some View {
        DashboardPanel(title: "Pull Requests", icon: "arrow.triangle.pull", badgeCount: viewModel.openPRCount) {
            if viewModel.pullRequests.isEmpty {
                Text("No pull requests")
                    .font(DesignTokens.fontBody)
                    .foregroundColor(DesignTokens.textMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                VStack(spacing: DesignTokens.spacingXS) {
                    ForEach(viewModel.pullRequests.prefix(6)) { pr in
                        PRRow(pr: pr)
                    }
                }
            }
        }
    }
}

struct PRRow: View {
    @EnvironmentObject var viewModel: DashboardViewModel
    let pr: PullRequest

    var statusColor: Color {
        if pr.isMerged { return DesignTokens.accentPurple }
        if pr.isOpen { return DesignTokens.accentGreen }
        return DesignTokens.statusNeutral
    }

    var body: some View {
        Button(action: {
            viewModel.openInBrowser(pr.html_url)
        }) {
            HStack(spacing: DesignTokens.spacingSM) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text("#\(pr.number)")
                    .font(DesignTokens.fontMono)
                    .foregroundColor(DesignTokens.textSecondary)

                if pr.draft {
                    Text("DRAFT")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(DesignTokens.textMuted)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(DesignTokens.bgTertiary)
                        .cornerRadius(2)
                }

                Text(pr.title)
                    .font(DesignTokens.fontBody)
                    .foregroundColor(DesignTokens.textPrimary)
                    .lineLimit(1)

                Spacer()

                if let additions = pr.additions, let deletions = pr.deletions {
                    HStack(spacing: 4) {
                        Text("+\(additions)")
                            .foregroundColor(DesignTokens.accentGreen)
                        Text("-\(deletions)")
                            .foregroundColor(DesignTokens.accentRed)
                    }
                    .font(DesignTokens.fontCaption)
                }

                UserIndicator(username: pr.user.login)
            }
            .padding(.vertical, DesignTokens.spacingXS)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Workflows Panel

struct WorkflowsPanel: View {
    @EnvironmentObject var viewModel: DashboardViewModel

    var body: some View {
        DashboardPanel(title: "Workflows", icon: "gearshape.2") {
            if viewModel.workflows.isEmpty {
                Text("No workflow runs")
                    .font(DesignTokens.fontBody)
                    .foregroundColor(DesignTokens.textMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                VStack(spacing: DesignTokens.spacingXS) {
                    ForEach(viewModel.workflows.prefix(5)) { workflow in
                        WorkflowRow(workflow: workflow)
                    }
                }
            }
        }
    }
}

struct WorkflowRow: View {
    @EnvironmentObject var viewModel: DashboardViewModel
    let workflow: WorkflowRun

    var body: some View {
        Button(action: {
            viewModel.openInBrowser(workflow.html_url)
        }) {
            HStack(spacing: DesignTokens.spacingSM) {
                if workflow.isRunning {
                    PulsingDot()
                } else {
                    StatusDot(isSuccess: workflow.isSuccess)
                }

                Text(workflow.name)
                    .font(DesignTokens.fontBody)
                    .foregroundColor(DesignTokens.textPrimary)
                    .lineLimit(1)

                Text(workflow.head_branch)
                    .font(DesignTokens.fontCaption)
                    .foregroundColor(DesignTokens.textMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(DesignTokens.bgTertiary)
                    .cornerRadius(DesignTokens.radiusSM)

                Spacer()

                Text(workflow.shortSha)
                    .font(DesignTokens.fontMono)
                    .foregroundColor(DesignTokens.textMuted)

                Text(workflow.created_at.relativeString)
                    .font(DesignTokens.fontCaption)
                    .foregroundColor(DesignTokens.textMuted)
            }
            .padding(.vertical, DesignTokens.spacingXS)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - UI Components

struct UserIndicator: View {
    let username: String

    var body: some View {
        Text(UserColors.initial(for: username))
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 20, height: 20)
            .background(UserColors.forUser(username))
            .cornerRadius(DesignTokens.radiusSM)
    }
}

struct StatusDot: View {
    var isOpen: Bool = true
    var isSuccess: Bool = true

    var color: Color {
        isOpen ? DesignTokens.statusSuccess :
        isSuccess ? DesignTokens.statusSuccess : DesignTokens.statusFailure
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }
}

struct PulsingDot: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(DesignTokens.statusPending)
            .frame(width: 8, height: 8)
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

struct LabelPill: View {
    let label: Issue.Label

    var labelColor: Color {
        Color(hex: label.color) ?? DesignTokens.textMuted
    }

    var body: some View {
        Text(label.name)
            .font(.system(size: 10))
            .foregroundColor(labelColor.luminance > 0.5 ? .black : .white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(labelColor)
            .cornerRadius(DesignTokens.radiusSM)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var viewModel: DashboardViewModel

    var body: some View {
        TabView {
            PollingSettingsView()
                .tabItem {
                    Label("Polling", systemImage: "clock.arrow.circlepath")
                }

            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 400, height: 250)
    }
}

struct PollingSettingsView: View {
    @EnvironmentObject var viewModel: DashboardViewModel

    var body: some View {
        Form {
            Section("Polling Intervals") {
                IntervalSlider(label: "Commits", value: $viewModel.commitInterval, range: 30...120)
                IntervalSlider(label: "Issues", value: $viewModel.issueInterval, range: 15...60)
                IntervalSlider(label: "Pull Requests", value: $viewModel.prInterval, range: 15...60)
                IntervalSlider(label: "Workflows", value: $viewModel.workflowInterval, range: 30...120)
                IntervalSlider(label: "Events", value: $viewModel.eventInterval, range: 15...60)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct IntervalSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(Int(value))s")
                .foregroundColor(.secondary)
                .frame(width: 40)
            Slider(value: $value, in: range, step: 5)
                .frame(width: 150)
        }
    }
}

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 48))
                .foregroundColor(DesignTokens.accentPrimary)

            Text("Async Dashboard")
                .font(.title)
                .fontWeight(.bold)

            Text("GitHub Monitoring for chickensintrees/async")
                .foregroundColor(.secondary)

            Text("Version 1.0")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            Text("Built with SwiftUI")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Extensions

extension Date {
    var relativeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        guard hexSanitized.count == 6 else { return nil }

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        self.init(
            red: Double((rgb & 0xFF0000) >> 16) / 255.0,
            green: Double((rgb & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgb & 0x0000FF) / 255.0
        )
    }

    var luminance: Double {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        NSColor(self).getRed(&red, green: &green, blue: &blue, alpha: nil)
        return 0.299 * Double(red) + 0.587 * Double(green) + 0.114 * Double(blue)
    }
}
